"""Exact native vLLM token-count boundary for reconstruction budgets."""

from __future__ import annotations

import http.client
import json
import ssl
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from typing import Any, Mapping, NoReturn
from urllib.parse import urlsplit

from .canonical import canonical_json_bytes
from .retrieval_service import RetrievalDependencyUnavailable, RetrievalServiceContractError


_SUPPORTED_SCHEMES = frozenset({"http", "https"})


class TokenizationTransportError(RuntimeError):
    """Stable content-free tokenizer transport failure."""

    def __init__(self, reason_code: str):
        self.reason_code = reason_code
        super().__init__(reason_code)


class TokenizationResponseError(ValueError):
    """Stable content-free tokenizer response rejection."""

    def __init__(self, reason_code: str):
        self.reason_code = reason_code
        super().__init__(reason_code)


def _text(value: Any, label: str, maximum: int) -> str:
    if (
        not isinstance(value, str)
        or not value.strip()
        or value != value.strip()
        or len(value) > maximum
        or "\x00" in value
        or "\r" in value
        or "\n" in value
    ):
        raise TokenizationTransportError(f"{label}_invalid")
    return value


@dataclass(frozen=True, slots=True)
class TokenizationEndpoint:
    url: str
    timeout_seconds: int = 120
    maximum_response_bytes: int = 4 * 1024 * 1024

    def __post_init__(self) -> None:
        _text(self.url, "endpoint", 2048)
        parsed = urlsplit(self.url)
        if (
            parsed.scheme not in _SUPPORTED_SCHEMES
            or not parsed.hostname
            or parsed.username is not None
            or parsed.password is not None
            or parsed.query
            or parsed.fragment
            or parsed.path != "/tokenize"
        ):
            raise TokenizationTransportError("endpoint_invalid")
        try:
            port = parsed.port
        except ValueError as error:
            raise TokenizationTransportError("endpoint_invalid") from error
        if port is not None and not 1 <= port <= 65535:
            raise TokenizationTransportError("endpoint_invalid")
        if type(self.timeout_seconds) is not int or not 1 <= self.timeout_seconds <= 300:
            raise TokenizationTransportError("timeout_invalid")
        if (
            type(self.maximum_response_bytes) is not int
            or not 65536 <= self.maximum_response_bytes <= 8 * 1024 * 1024
        ):
            raise TokenizationTransportError("response_limit_invalid")

    @property
    def parsed(self):
        return urlsplit(self.url)


@dataclass(frozen=True, slots=True)
class PreparedTokenizationRequest:
    scheme: str
    host: str
    port: int
    path: str
    headers: dict[str, str]
    body: bytes
    timeout_seconds: int
    maximum_response_bytes: int


@dataclass(frozen=True, slots=True)
class TokenizationHTTPResponse:
    status: int
    content_type: str
    body: bytes


def prepare_tokenization_request(
    endpoint: TokenizationEndpoint,
    *,
    model: str,
    prompt: str,
    api_key: str,
) -> PreparedTokenizationRequest:
    if not isinstance(endpoint, TokenizationEndpoint):
        raise TokenizationTransportError("request_invalid")
    served_model = _text(model, "model", 256)
    credential = _text(api_key, "credential", 16384)
    if (
        not isinstance(prompt, str)
        or not prompt.strip()
        or len(prompt) > 1048576
        or "\x00" in prompt
    ):
        raise TokenizationTransportError("prompt_invalid")
    parsed = endpoint.parsed
    return PreparedTokenizationRequest(
        scheme=parsed.scheme,
        host=parsed.hostname or "",
        port=parsed.port or (443 if parsed.scheme == "https" else 80),
        path=parsed.path,
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {credential}",
            "Content-Type": "application/json",
        },
        body=canonical_json_bytes(
            {
                "add_special_tokens": True,
                "model": served_model,
                "prompt": prompt,
                "return_token_strs": False,
            }
        ),
        timeout_seconds=endpoint.timeout_seconds,
        maximum_response_bytes=endpoint.maximum_response_bytes,
    )


def prepare_chat_tokenization_request(
    endpoint: TokenizationEndpoint,
    *,
    model: str,
    messages: Sequence[Mapping[str, str]],
    chat_template_kwargs: Mapping[str, Any],
    api_key: str,
) -> PreparedTokenizationRequest:
    """Prepare exact chat-template admission for the generation message vector."""

    if not isinstance(endpoint, TokenizationEndpoint):
        raise TokenizationTransportError("request_invalid")
    served_model = _text(model, "model", 256)
    credential = _text(api_key, "credential", 16384)
    if (
        not isinstance(messages, Sequence)
        or isinstance(messages, (str, bytes))
        or not messages
        or any(
            not isinstance(message, Mapping)
            or set(message) != {"content", "role"}
            or message["role"] not in {"system", "user", "assistant"}
            or not isinstance(message["content"], str)
            or not message["content"].strip()
            or "\x00" in message["content"]
            for message in messages
        )
        or dict(chat_template_kwargs) != {"enable_thinking": False}
    ):
        raise TokenizationTransportError("chat_request_invalid")
    parsed = endpoint.parsed
    return PreparedTokenizationRequest(
        scheme=parsed.scheme,
        host=parsed.hostname or "",
        port=parsed.port or (443 if parsed.scheme == "https" else 80),
        path=parsed.path,
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {credential}",
            "Content-Type": "application/json",
        },
        body=canonical_json_bytes(
            {
                "add_generation_prompt": True,
                "add_special_tokens": False,
                "chat_template_kwargs": {"enable_thinking": False},
                "continue_final_message": False,
                "messages": [dict(message) for message in messages],
                "model": served_model,
                "return_token_strs": False,
            }
        ),
        timeout_seconds=endpoint.timeout_seconds,
        maximum_response_bytes=endpoint.maximum_response_bytes,
    )


def native_tokenization_exchange(
    prepared: PreparedTokenizationRequest,
    *,
    tls_context: ssl.SSLContext | None = None,
) -> TokenizationHTTPResponse:
    connection: http.client.HTTPConnection | None = None
    try:
        if prepared.scheme == "https":
            connection = http.client.HTTPSConnection(
                prepared.host,
                prepared.port,
                timeout=prepared.timeout_seconds,
                context=tls_context,
            )
        else:
            connection = http.client.HTTPConnection(
                prepared.host, prepared.port, timeout=prepared.timeout_seconds
            )
        connection.request("POST", prepared.path, body=prepared.body, headers=prepared.headers)
        response = connection.getresponse()
        body = response.read(prepared.maximum_response_bytes + 1)
        if len(body) > prepared.maximum_response_bytes:
            raise TokenizationTransportError("response_too_large")
        return TokenizationHTTPResponse(
            response.status,
            response.getheader("Content-Type", ""),
            body,
        )
    except TokenizationTransportError:
        raise
    except (OSError, TimeoutError, http.client.HTTPException, ssl.SSLError) as error:
        raise TokenizationTransportError("upstream_unavailable") from error
    finally:
        if connection is not None:
            connection.close()


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise TokenizationResponseError("tokenization_json_duplicate_field")
        result[key] = value
    return result


def _reject_constant(_value: str) -> NoReturn:
    raise TokenizationResponseError("tokenization_json_nonfinite_number")


def validate_tokenization_response(
    response: TokenizationHTTPResponse,
    *,
    minimum_model_length: int,
) -> int:
    if not isinstance(response, TokenizationHTTPResponse):
        raise TokenizationResponseError("tokenization_response_invalid")
    if response.status != 200:
        raise TokenizationResponseError("tokenization_upstream_http_error")
    if response.content_type.split(";", 1)[0].strip().lower() != "application/json":
        raise TokenizationResponseError("tokenization_content_type_invalid")
    try:
        document = json.loads(
            response.body.decode("utf-8"),
            object_pairs_hook=_reject_duplicates,
            parse_constant=_reject_constant,
        )
    except TokenizationResponseError:
        raise
    except (UnicodeError, json.JSONDecodeError) as error:
        raise TokenizationResponseError("tokenization_json_invalid") from error
    if not isinstance(document, Mapping) or set(document) not in (
        {"count", "max_model_len", "tokens"},
        {"count", "max_model_len", "tokens", "token_strs"},
    ):
        raise TokenizationResponseError("tokenization_schema_invalid")
    if "token_strs" in document and document["token_strs"] not in (None, []):
        raise TokenizationResponseError("tokenization_schema_invalid")
    count = document["count"]
    maximum = document["max_model_len"]
    tokens = document["tokens"]
    if (
        type(count) is not int
        or count < 1
        or type(maximum) is not int
        or maximum < minimum_model_length
        or not isinstance(tokens, list)
        or len(tokens) != count
        or any(type(item) is not int or item < 0 for item in tokens)
    ):
        raise TokenizationResponseError("tokenization_result_invalid")
    return count


TokenizationExchange = Callable[[PreparedTokenizationRequest], TokenizationHTTPResponse]
CredentialProvider = Callable[[], str]


@dataclass(frozen=True, slots=True)
class NativeGenerationTokenCounter:
    endpoint: TokenizationEndpoint
    served_model: str
    minimum_model_length: int
    credential_provider: CredentialProvider
    exchange: TokenizationExchange = native_tokenization_exchange

    def __post_init__(self) -> None:
        _text(self.served_model, "model", 256)
        if type(self.minimum_model_length) is not int or self.minimum_model_length < 1:
            raise RetrievalServiceContractError("token counter model length is invalid")
        if not callable(self.credential_provider) or not callable(self.exchange):
            raise RetrievalServiceContractError("token counter dependency is invalid")

    def __call__(self, text: str) -> int:
        try:
            credential = self.credential_provider()
            prepared = prepare_tokenization_request(
                self.endpoint,
                model=self.served_model,
                prompt=text,
                api_key=credential,
            )
            response = self.exchange(prepared)
            return validate_tokenization_response(
                response,
                minimum_model_length=self.minimum_model_length,
            )
        except (TokenizationTransportError, TokenizationResponseError) as error:
            raise RetrievalDependencyUnavailable("generation_tokenizer_failed") from error
        except RetrievalDependencyUnavailable:
            raise
        except Exception as error:
            raise RetrievalDependencyUnavailable("generation_tokenizer_failed") from error

    def count_messages(
        self,
        messages: Sequence[Mapping[str, str]],
        chat_template_kwargs: Mapping[str, Any],
    ) -> int:
        """Count the exact no-thinking messages later sent to chat completion."""

        try:
            credential = self.credential_provider()
            prepared = prepare_chat_tokenization_request(
                self.endpoint,
                model=self.served_model,
                messages=messages,
                chat_template_kwargs=chat_template_kwargs,
                api_key=credential,
            )
            response = self.exchange(prepared)
            return validate_tokenization_response(
                response,
                minimum_model_length=self.minimum_model_length,
            )
        except (TokenizationTransportError, TokenizationResponseError) as error:
            raise RetrievalDependencyUnavailable("generation_tokenizer_failed") from error
        except RetrievalDependencyUnavailable:
            raise
        except Exception as error:
            raise RetrievalDependencyUnavailable("generation_tokenizer_failed") from error
