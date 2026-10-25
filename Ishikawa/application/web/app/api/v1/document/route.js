import {
  buildDocumentViewRequest,
  validateDocumentViewResponse,
  validateTransportError,
} from "../../../../lib/chat-contract.mjs";
import { loadServerRuntimeConfig } from "../../../../lib/runtime-config.mjs";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const SAFE_HEADERS = {
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};
const MAXIMUM_RESPONSE_BYTES = 4 * 1024 * 1024;

function safeError(status, code, message) {
  return Response.json(
    { code, message, schema: "ishikawa.web-error.v1" },
    { headers: SAFE_HEADERS, status },
  );
}

export async function POST(incoming) {
  if (incoming.headers.get("content-type") !== "application/json") {
    return safeError(415, "WEB_MEDIA_TYPE_UNSUPPORTED", "Content-Type must be application/json.");
  }
  let request;
  try {
    const raw = await incoming.json();
    request = buildDocumentViewRequest(
      raw.source_id,
      raw.section_offset,
      raw.section_limit,
    );
    if (raw.schema !== request.schema || Object.keys(raw).length !== 4) {
      throw new Error("document_request_invalid");
    }
  } catch {
    return safeError(400, "WEB_DOCUMENT_REQUEST_INVALID", "The document request is invalid.");
  }

  try {
    const { retrievalBaseUrl } = loadServerRuntimeConfig();
    const upstream = await fetch(`${retrievalBaseUrl}/v1/document`, {
      body: JSON.stringify(request),
      cache: "no-store",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      method: "POST",
      signal: AbortSignal.timeout(15000),
    });
    const bytes = new Uint8Array(await upstream.arrayBuffer());
    if (bytes.length < 1 || bytes.length > MAXIMUM_RESPONSE_BYTES) {
      return safeError(502, "WEB_UPSTREAM_INVALID", "The document response was invalid.");
    }
    const value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    if (upstream.status === 200) {
      validateDocumentViewResponse(value, request.source_id);
    } else {
      validateTransportError(value);
    }
    return new Response(bytes, {
      headers: { ...SAFE_HEADERS, "Content-Type": "application/json" },
      status: upstream.status,
    });
  } catch {
    return safeError(503, "WEB_DOCUMENT_UNAVAILABLE", "Document viewing is temporarily unavailable.");
  }
}
