import { loadServerRuntimeConfig } from "../../../lib/runtime-config.mjs";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const SAFE_HEADERS = {
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

export async function GET() {
  try {
    const { retrievalBaseUrl } = loadServerRuntimeConfig();
    const upstream = await fetch(`${retrievalBaseUrl}/ready`, {
      cache: "no-store",
      headers: { Accept: "application/json" },
      method: "GET",
      signal: AbortSignal.timeout(5000),
    });
    const body = await upstream.json();
    if (
      upstream.status === 200 &&
      body?.schema === "ishikawa.health.v1" &&
      body?.status === "ready"
    ) {
      return Response.json(
        { schema: "ishikawa.web-health.v1", status: "ready" },
        { headers: SAFE_HEADERS, status: 200 },
      );
    }
  } catch {
    // Readiness is deliberately content-free and fail-closed.
  }
  return Response.json(
    { schema: "ishikawa.web-health.v1", status: "not-ready" },
    { headers: SAFE_HEADERS, status: 503 },
  );
}
