import {
  MAXIMUM_REQUEST_BYTES,
  validateChatRequestPayload,
  validateChatResponse,
  validateTransportError,
} from "../../../../lib/chat-contract.mjs";
import { loadServerRuntimeConfig } from "../../../../lib/runtime-config.mjs";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const MAXIMUM_RESPONSE_BYTES = 4 * 1024 * 1024;
// The Retrieval API owns bounded model timeouts and one approved generation
// retry. This outer deadline spans that complete sequential workflow instead
// of misreporting a healthy, still-processing service as unavailable.
const RETRIEVAL_REQUEST_TIMEOUT_MS = 600_000;
const SAFE_HEADERS = {
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

function safeError(status, code, message) {
  return Response.json(
    { code, message, schema: "ishikawa.web-error.v1" },
    { headers: SAFE_HEADERS, status },
  );
}

function decodeJson(bytes) {
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
}

export async function POST(incoming) {
  if (incoming.headers.get("content-type") !== "application/json") {
    return safeError(415, "WEB_MEDIA_TYPE_UNSUPPORTED", "Content-Type must be application/json.");
  }
  let requestBytes;
  let requestValue;
  try {
    requestBytes = new Uint8Array(await incoming.arrayBuffer());
    if (requestBytes.length < 1 || requestBytes.length > MAXIMUM_REQUEST_BYTES) {
      return safeError(413, "WEB_REQUEST_SIZE_INVALID", "The request is outside the accepted size.");
    }
    requestValue = decodeJson(requestBytes);
    validateChatRequestPayload(requestValue);
  } catch {
    return safeError(400, "WEB_REQUEST_INVALID", "The request body is invalid.");
  }

  try {
    const { retrievalBaseUrl } = loadServerRuntimeConfig();
    const upstream = await fetch(`${retrievalBaseUrl}/v1/chat`, {
      body: requestBytes,
      cache: "no-store",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      method: "POST",
      signal: AbortSignal.timeout(RETRIEVAL_REQUEST_TIMEOUT_MS),
    });
    const responseBytes = new Uint8Array(await upstream.arrayBuffer());
    if (responseBytes.length < 1 || responseBytes.length > MAXIMUM_RESPONSE_BYTES) {
      return safeError(502, "WEB_UPSTREAM_INVALID", "The retrieval response was invalid.");
    }
    const responseValue = decodeJson(responseBytes);
    if (upstream.status === 200) {
      validateChatResponse(responseValue, requestValue);
    } else {
      validateTransportError(responseValue);
    }
    return new Response(responseBytes, {
      headers: { ...SAFE_HEADERS, "Content-Type": "application/json" },
      status: upstream.status,
    });
  } catch (error) {
    if (error?.name === "TimeoutError") {
      return safeError(
        504,
        "WEB_RETRIEVAL_TIMEOUT",
        "The retrieval request timed out before a response was returned.",
      );
    }
    return safeError(503, "WEB_RETRIEVAL_UNAVAILABLE", "The retrieval service is unavailable.");
  }
}
