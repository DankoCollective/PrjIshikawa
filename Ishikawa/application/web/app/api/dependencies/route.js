import { loadServerRuntimeConfig } from "../../../lib/runtime-config.mjs";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const SAFE_HEADERS = {
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};
const STATES = new Set(["available", "unavailable"]);

function unavailable() {
  return Response.json(
    {
      gemma: "unavailable",
      nomic: "unavailable",
      schema: "ishikawa.web-dependency-health.v1",
    },
    { headers: SAFE_HEADERS, status: 200 },
  );
}

export async function GET() {
  try {
    const { retrievalBaseUrl } = loadServerRuntimeConfig();
    const upstream = await fetch(`${retrievalBaseUrl}/dependencies`, {
      cache: "no-store",
      headers: { Accept: "application/json" },
      method: "GET",
      signal: AbortSignal.timeout(5000),
    });
    const body = await upstream.json();
    if (
      upstream.status === 200 &&
      body?.schema === "ishikawa.dependency-health.v1" &&
      STATES.has(body.gemma) &&
      STATES.has(body.nomic) &&
      Object.keys(body).sort().join(",") === "gemma,nomic,schema"
    ) {
      return Response.json(
        {
          gemma: body.gemma,
          nomic: body.nomic,
          schema: "ishikawa.web-dependency-health.v1",
        },
        { headers: SAFE_HEADERS, status: 200 },
      );
    }
  } catch {
    // The display fails closed without exposing endpoint or transport details.
  }
  return unavailable();
}
