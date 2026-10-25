import assert from "node:assert/strict";
import test from "node:test";

import {
  buildDocumentViewRequest,
  buildChatRequest,
  boundedHistory,
  createOpaqueIdentity,
  responseDisplayText,
  stabilizeChatSourceLabels,
  validateChatRequestPayload,
  validateChatResponse,
  validateDocumentViewResponse,
  validateTransportError,
} from "../lib/chat-contract.mjs";

const identity = (character) => character.repeat(64);

function source() {
  return {
    display_name: "Incident Reporting Procedure",
    document_class: "policy_sop",
    document_identifier: "99 TST 2003",
    document_key: "procedure.incident-reporting",
    excerpts: [
      {
        anchor: { kind: "step", label: "Step 2" },
        citation_id: identity("f"),
        excerpt: "Reports are submitted promptly.",
        page_end: 2,
        page_start: 2,
        structural_path: ["Incident Reporting", "Submission"],
      },
    ],
    has_additional_sections: true,
    page_count: 3,
    source_id: identity("e"),
    source_label: "Source 1",
  };
}

function priorMessages(pairCount = 1) {
  const result = [];
  for (let index = 0; index < pairCount; index += 1) {
    result.push({
      content: `Question ${index + 1}`,
      historyTurnId: index.toString(16).padStart(64, "0"),
      role: "user",
      sources: [],
    });
    result.push({
      content: `Answer ${index + 1}`,
      historyTurnId: (index + 100).toString(16).padStart(64, "0"),
      role: "assistant",
      sources: index === 0 ? [source()] : [],
    });
  }
  return result;
}

test("opaque identities contain exactly 64 lowercase hexadecimal characters", () => {
  const bytes = new Uint8Array(32).fill(171);
  assert.equal(createOpaqueIdentity(bytes), "ab".repeat(32));
});

test("history retains the newest six complete exchanges", () => {
  const selected = boundedHistory(priorMessages(8));
  assert.equal(selected.length, 12);
  assert.equal(selected[0].content, "Question 3");
  assert.equal(selected.at(-1).content, "Answer 8");
});

test("request carries prior sources and uses the exact versioned fields", () => {
  const request = buildChatRequest({
    conversationId: identity("a"),
    message: "What else does Source 1 say?",
    priorMessages: priorMessages(),
    turnId: identity("d"),
  });
  assert.deepEqual(Object.keys(request).sort(), [
    "conversation_id",
    "filters",
    "history",
    "message",
    "schema",
    "source_references",
    "turn_id",
  ]);
  assert.deepEqual(request.source_references, [
    { citation_id: null, source_id: identity("e"), source_label: "Source 1" },
  ]);
  assert.equal(validateChatRequestPayload(request), request);
});

test("source labels remain unique and stable across one browser chat", () => {
  const prior = priorMessages();
  const repeated = { ...source(), source_label: "Source 4" };
  const additional = {
    ...source(),
    display_name: "Controlled Materials Access Policy",
    document_identifier: "99 TST 2001",
    document_key: "policy.controlled-materials",
    source_id: identity("9"),
    source_label: "Source 1",
  };
  const stabilized = stabilizeChatSourceLabels(prior, [repeated, additional]);
  assert.equal(stabilized[0].source_label, "Source 1");
  assert.equal(stabilized[1].source_label, "Source 2");
  assert.equal(stabilized[1].document_identifier, "99 TST 2001");
});

test("request rejects an odd history and an unknown field", () => {
  assert.throws(
    () => buildChatRequest({
      conversationId: identity("a"),
      message: "Question",
      priorMessages: priorMessages().slice(0, 1),
      turnId: identity("d"),
    }),
    /history_order_invalid/u,
  );
  const request = buildChatRequest({
    conversationId: identity("a"),
    message: "Question",
    priorMessages: [],
    turnId: identity("d"),
  });
  request.method_profile = "not-allowed";
  assert.throws(() => validateChatRequestPayload(request), /request_fields_invalid/u);
});

test("answered response requires segment-derived text and resolvable citations", () => {
  const request = buildChatRequest({
    conversationId: identity("a"),
    message: "How are reports submitted?",
    priorMessages: [],
    turnId: identity("d"),
  });
  const response = {
    clarification: null,
    context_budget: { token_limit: 32768, tokens_remaining: 24576, tokens_used: 8192 },
    conversation_id: identity("a"),
    error: null,
    request_id: identity("1"),
    diagnostics: {
      api_processing_ms: 100,
      context_tokens: { limit: 32768, remaining: 24576, used: 8192 },
      gemma_tokens: { completion: 20, prompt: 100, total: 120 },
      generation_retry: false,
      lane_states: { exact: "not_applicable", lexical: "pass", vector: "pass" },
      nomic_query_tokens: 12,
      prompt_target_tokens: 8192,
      relevance_reason_code: "CITABLE_EVIDENCE_SUPPORT_QUALIFIED",
      result_counts: { authorized: 4, cited: 1, fused: 6, reconstructed: 3 },
      selected_group_order: [`${identity("e")}:responsive-section`],
      sufficiency_reason_code: "EVIDENCE_SUFFICIENT",
      timings_ms: {
        generation: 70,
        query_resolution: 4,
        response_build: 2,
        retrieval: 20,
        retrieval_detail: { fusion: 1, lexical_sql: 2, nomic: 8, reconstruction: 5, tokenization: 3, vector_sql: 1 },
        scope: 4,
      },
    },
    schema: "ishikawa.chat-response.v5",
    segments: [{ citation_ids: [identity("f")], text: "Reports are submitted promptly." }],
    sources: [source()],
    status: "answered",
    turn_id: identity("d"),
  };
  assert.equal(validateChatResponse(response, request), response);
  assert.equal(responseDisplayText(response), "Reports are submitted promptly.");
  response.answer = "Uncited model prose.";
  assert.throws(() => validateChatResponse(response, request), /response_fields_invalid/u);
});

test("clarification and safe transport errors remain distinct", () => {
  const request = buildChatRequest({
    conversationId: identity("a"),
    message: "What is the rule?",
    priorMessages: [],
    turnId: identity("d"),
  });
  const clarification = {
    clarification: "Which policy do you mean?",
    context_budget: null,
    conversation_id: identity("a"),
    error: null,
    request_id: identity("1"),
    diagnostics: {
      api_processing_ms: 3,
      context_tokens: null,
      gemma_tokens: null,
      generation_retry: false,
      lane_states: null,
      nomic_query_tokens: null,
      prompt_target_tokens: null,
      relevance_reason_code: null,
      result_counts: null,
      selected_group_order: null,
      sufficiency_reason_code: null,
      timings_ms: { generation: 0, query_resolution: 0, response_build: 0, retrieval: 0, retrieval_detail: null, scope: 2 },
    },
    schema: "ishikawa.chat-response.v5",
    segments: [],
    sources: [],
    status: "clarification-required",
    turn_id: identity("d"),
  };
  assert.equal(responseDisplayText(validateChatResponse(clarification, request)), "Which policy do you mean?");
  const transport = {
    error: { code: "HTTP_SERVICE_BUSY", message: "The service is temporarily busy." },
    request_id: identity("2"),
    schema: "ishikawa.transport-error.v1",
  };
  assert.equal(validateTransportError(transport), transport);
});

test("document viewing is exact, progressive, and source-bound", () => {
  const request = buildDocumentViewRequest(identity("e"), 0, 4);
  assert.equal(request.schema, "ishikawa.document-view-request.v1");
  const response = {
    complete: false,
    next_section_offset: 1,
    schema: "ishikawa.document-view-response.v2",
    sections: [{
      heading: "I. Purpose and Scope",
      ordinal: 0,
      units: [{
        kind: "paragraph",
        page_end: 1,
        page_start: 1,
        structural_path: ["I. Purpose and Scope"],
        text: "This policy establishes synthetic controls.",
      }],
    }],
    source: {
      display_name: "Controlled Materials Access Policy",
      document_class: "policy_sop",
      document_identifier: "99 TST 2001",
      document_key: "policy.controlled-materials",
      page_count: 3,
      source_id: identity("e"),
    },
    total_sections: 5,
  };
  assert.equal(validateDocumentViewResponse(response, identity("e")), response);
  assert.throws(
    () => validateDocumentViewResponse(response, identity("9")),
    /document_source_invalid/u,
  );
});
