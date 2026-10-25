/** Client-side construction and validation for the versioned chat boundary. */

export const REQUEST_SCHEMA = "ishikawa.chat-request.v1";
export const RESPONSE_SCHEMA = "ishikawa.chat-response.v5";
export const DOCUMENT_REQUEST_SCHEMA = "ishikawa.document-view-request.v1";
export const DOCUMENT_RESPONSE_SCHEMA = "ishikawa.document-view-response.v2";
export const TRANSPORT_ERROR_SCHEMA = "ishikawa.transport-error.v1";
export const MAXIMUM_REQUEST_BYTES = 262144;
export const MAXIMUM_QUESTION_CHARACTERS = 16384;
export const MAXIMUM_HISTORY_TURNS = 12;
export const MAXIMUM_HISTORY_CHARACTERS = 65536;
export const MAXIMUM_SOURCE_REFERENCES = 20;

const HEX_IDENTITY = /^[0-9a-f]{64}$/u;
const SOURCE_LABEL = /^Source [1-9][0-9]*$/u;
const CLASS_ID = /^[a-z][a-z0-9_]{1,63}$/u;
const DOCUMENT_KEY = /^[a-z0-9]+(?:[._-][a-z0-9]+)*$/u;
const ERROR_CODE = /^[A-Z][A-Z0-9_]{2,63}$/u;
const STATUSES = new Set([
  "answered",
  "clarification-required",
  "insufficient-evidence",
  "out-of-scope",
  "security-rejected",
  "context-limit",
  "temporarily-unavailable",
  "internal-error",
]);
const ANCHOR_KINDS = new Set(["table", "row", "form", "field", "procedure", "step"]);
const DOCUMENT_UNIT_KINDS = new Set([
  "paragraph", "list_item", "procedure_step", "table", "table_context",
  "form", "form_field", "page_status",
]);

function fail(reason) {
  throw new Error(reason);
}

function exactObject(value, fields, reason) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    fail(reason);
  }
  const actual = Object.keys(value).sort();
  const expected = [...fields].sort();
  if (actual.length !== expected.length || actual.some((item, index) => item !== expected[index])) {
    fail(reason);
  }
  return value;
}

function identity(value, reason) {
  if (typeof value !== "string" || !HEX_IDENTITY.test(value)) {
    fail(reason);
  }
  return value;
}

function boundedText(value, maximum, reason) {
  if (
    typeof value !== "string" ||
    value.trim() !== value ||
    value.length < 1 ||
    value.length > maximum ||
    value.includes("\u0000")
  ) {
    fail(reason);
  }
  return value;
}

function unique(values) {
  return new Set(values).size === values.length;
}

export function createOpaqueIdentity(randomBytes) {
  const bytes = randomBytes ?? globalThis.crypto?.getRandomValues(new Uint8Array(32));
  if (!(bytes instanceof Uint8Array) || bytes.length !== 32) {
    fail("identity_entropy_invalid");
  }
  return Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
}

export function boundedHistory(messages) {
  if (!Array.isArray(messages)) {
    fail("history_messages_invalid");
  }
  const history = messages.map((message) => ({
    turn_id: identity(message.historyTurnId, "history_turn_id_invalid"),
    role: message.role,
    content: boundedText(message.content, 131072, "history_content_invalid"),
  }));
  if (
    history.length % 2 !== 0 ||
    history.some((turn, index) => turn.role !== (index % 2 === 0 ? "user" : "assistant")) ||
    !unique(history.map((turn) => turn.turn_id))
  ) {
    fail("history_order_invalid");
  }
  let selected = history.slice(-MAXIMUM_HISTORY_TURNS);
  while (
    selected.length > 0 &&
    selected.reduce((total, turn) => total + turn.content.length, 0) > MAXIMUM_HISTORY_CHARACTERS
  ) {
    selected = selected.slice(2);
  }
  return selected;
}

export function collectSourceReferences(messages) {
  if (!Array.isArray(messages)) {
    fail("source_messages_invalid");
  }
  const references = [];
  const sourceIds = new Set();
  const sourceLabels = new Set();
  for (const message of messages) {
    for (const source of message.sources ?? []) {
      if (references.length >= MAXIMUM_SOURCE_REFERENCES) {
        return references;
      }
      if (sourceIds.has(source.source_id) || sourceLabels.has(source.source_label)) {
        continue;
      }
      identity(source.source_id, "source_id_invalid");
      if (typeof source.source_label !== "string" || !SOURCE_LABEL.test(source.source_label)) {
        fail("source_label_invalid");
      }
      sourceIds.add(source.source_id);
      sourceLabels.add(source.source_label);
      references.push({
        citation_id: null,
        source_id: source.source_id,
        source_label: source.source_label,
      });
    }
  }
  return references;
}

export function stabilizeChatSourceLabels(messages, sources) {
  if (!Array.isArray(messages) || !Array.isArray(sources)) {
    fail("source_label_inputs_invalid");
  }
  const labelBySourceId = new Map();
  const usedLabels = new Set();
  for (const message of messages) {
    for (const source of message.sources ?? []) {
      if (
        typeof source.source_id !== "string" ||
        typeof source.source_label !== "string" ||
        !HEX_IDENTITY.test(source.source_id) ||
        !SOURCE_LABEL.test(source.source_label)
      ) {
        fail("source_label_history_invalid");
      }
      if (!labelBySourceId.has(source.source_id) && !usedLabels.has(source.source_label)) {
        labelBySourceId.set(source.source_id, source.source_label);
        usedLabels.add(source.source_label);
      }
    }
  }
  let nextNumber = 1;
  return sources.map((source) => {
    const existing = labelBySourceId.get(source.source_id);
    if (existing) {
      return source.source_label === existing ? source : { ...source, source_label: existing };
    }
    while (usedLabels.has(`Source ${nextNumber}`)) {
      nextNumber += 1;
    }
    const sourceLabel = `Source ${nextNumber}`;
    nextNumber += 1;
    labelBySourceId.set(source.source_id, sourceLabel);
    usedLabels.add(sourceLabel);
    return source.source_label === sourceLabel ? source : { ...source, source_label: sourceLabel };
  });
}

export function buildChatRequest({
  conversationId,
  turnId,
  message,
  priorMessages,
  filters = { document_classes: [], document_keys: [] },
}) {
  identity(conversationId, "conversation_id_invalid");
  identity(turnId, "turn_id_invalid");
  const question = boundedText(message, MAXIMUM_QUESTION_CHARACTERS, "message_invalid");
  const history = boundedHistory(priorMessages);
  if (history.some((turn) => turn.turn_id === turnId)) {
    fail("turn_id_reused");
  }
  exactObject(filters, ["document_classes", "document_keys"], "filters_invalid");
  for (const [name, pattern] of [
    ["document_classes", CLASS_ID],
    ["document_keys", DOCUMENT_KEY],
  ]) {
    const values = filters[name];
    if (
      !Array.isArray(values) ||
      values.length > 20 ||
      !unique(values) ||
      values.some((value) => typeof value !== "string" || !pattern.test(value))
    ) {
      fail("filters_invalid");
    }
  }
  const request = {
    conversation_id: conversationId,
    filters: {
      document_classes: [...filters.document_classes],
      document_keys: [...filters.document_keys],
    },
    history,
    message: question,
    schema: REQUEST_SCHEMA,
    source_references: collectSourceReferences(priorMessages),
    turn_id: turnId,
  };
  if (new TextEncoder().encode(JSON.stringify(request)).length > MAXIMUM_REQUEST_BYTES) {
    fail("request_size_invalid");
  }
  return request;
}

export function validateChatRequestPayload(value) {
  const root = exactObject(
    value,
    ["conversation_id", "filters", "history", "message", "schema", "source_references", "turn_id"],
    "request_fields_invalid",
  );
  if (root.schema !== REQUEST_SCHEMA) {
    fail("request_schema_invalid");
  }
  const rebuilt = buildChatRequest({
    conversationId: root.conversation_id,
    turnId: root.turn_id,
    message: root.message,
    priorMessages: root.history.map((turn) => ({
      content: turn.content,
      historyTurnId: turn.turn_id,
      role: turn.role,
      sources: [],
    })),
    filters: root.filters,
  });
  if (
    rebuilt.history.length !== root.history.length ||
    !Array.isArray(root.source_references) ||
    root.source_references.length > MAXIMUM_SOURCE_REFERENCES
  ) {
    fail("request_limit_invalid");
  }
  const sourceIds = [];
  const sourceLabels = [];
  const citationIds = [];
  for (const value of root.source_references) {
    const reference = exactObject(
      value,
      ["citation_id", "source_id", "source_label"],
      "request_source_reference_invalid",
    );
    sourceIds.push(identity(reference.source_id, "request_source_reference_invalid"));
    if (typeof reference.source_label !== "string" || !SOURCE_LABEL.test(reference.source_label)) {
      fail("request_source_reference_invalid");
    }
    sourceLabels.push(reference.source_label);
    if (reference.citation_id !== null) {
      citationIds.push(identity(reference.citation_id, "request_source_reference_invalid"));
    }
  }
  if (!unique(sourceIds) || !unique(sourceLabels) || !unique(citationIds)) {
    fail("request_source_reference_duplicate");
  }
  return root;
}

function validateExcerpt(value, citationIds) {
  const excerpt = exactObject(
    value,
    ["anchor", "citation_id", "excerpt", "page_end", "page_start", "structural_path"],
    "response_excerpt_invalid",
  );
  identity(excerpt.citation_id, "response_citation_id_invalid");
  boundedText(excerpt.excerpt, 262144, "response_excerpt_invalid");
  if (
    !Number.isInteger(excerpt.page_start) ||
    !Number.isInteger(excerpt.page_end) ||
    excerpt.page_start < 1 ||
    excerpt.page_end < excerpt.page_start ||
    !Array.isArray(excerpt.structural_path) ||
    excerpt.structural_path.some((item) => typeof item !== "string" || !item.trim())
  ) {
    fail("response_excerpt_invalid");
  }
  if (excerpt.anchor !== null) {
    const anchor = exactObject(excerpt.anchor, ["kind", "label"], "response_anchor_invalid");
    if (!ANCHOR_KINDS.has(anchor.kind)) {
      fail("response_anchor_invalid");
    }
    boundedText(anchor.label, 512, "response_anchor_invalid");
  }
  if (citationIds.has(excerpt.citation_id)) {
    fail("response_citation_duplicate");
  }
  citationIds.add(excerpt.citation_id);
  return excerpt;
}

function validateSources(values) {
  if (!Array.isArray(values) || values.length < 1 || values.length > 20) {
    fail("response_sources_invalid");
  }
  const sourceIds = new Set();
  const sourceLabels = new Set();
  const citationIds = new Set();
  for (const value of values) {
    const source = exactObject(
      value,
      [
        "display_name",
        "document_class",
        "document_identifier",
        "document_key",
        "excerpts",
        "has_additional_sections",
        "page_count",
        "source_id",
        "source_label",
      ],
      "response_source_invalid",
    );
    identity(source.source_id, "response_source_id_invalid");
    boundedText(source.display_name, 512, "response_display_name_invalid");
    if (
      !SOURCE_LABEL.test(source.source_label) ||
      !CLASS_ID.test(source.document_class) ||
      !DOCUMENT_KEY.test(source.document_key) ||
      (source.document_identifier !== null &&
        (typeof source.document_identifier !== "string" ||
          boundedText(source.document_identifier, 512, "response_document_identifier_invalid") !== source.document_identifier)) ||
      typeof source.has_additional_sections !== "boolean"
      || !Number.isInteger(source.page_count)
      || source.page_count < 1
      || source.page_count > 1000000
    ) {
      fail("response_source_invalid");
    }
    if (sourceIds.has(source.source_id) || sourceLabels.has(source.source_label)) {
      fail("response_source_duplicate");
    }
    sourceIds.add(source.source_id);
    sourceLabels.add(source.source_label);
    if (!Array.isArray(source.excerpts) || source.excerpts.length < 1 || source.excerpts.length > 20) {
      fail("response_excerpts_invalid");
    }
    source.excerpts.forEach((excerpt) => validateExcerpt(excerpt, citationIds));
    if (source.excerpts.some((excerpt) => excerpt.page_end > source.page_count)) {
      fail("response_page_count_invalid");
    }
  }
  return citationIds;
}

function validateContextBudget(value) {
  const budget = exactObject(
    value,
    ["token_limit", "tokens_remaining", "tokens_used"],
    "response_context_budget_invalid",
  );
  if (
    !Number.isInteger(budget.token_limit) ||
    !Number.isInteger(budget.tokens_used) ||
    !Number.isInteger(budget.tokens_remaining) ||
    budget.token_limit < 1 ||
    budget.tokens_used < 0 ||
    budget.tokens_used > budget.token_limit ||
    budget.tokens_remaining !== budget.token_limit - budget.tokens_used
  ) {
    fail("response_context_budget_invalid");
  }
  return budget;
}

function nullableCount(value, reason) {
  if (value !== null && (!Number.isInteger(value) || value < 0 || value > 100000000)) {
    fail(reason);
  }
  return value;
}

function validateDiagnostics(value) {
  const diagnostics = exactObject(
    value,
    [
      "api_processing_ms",
      "context_tokens",
      "gemma_tokens",
      "generation_retry",
      "lane_states",
      "nomic_query_tokens",
      "prompt_target_tokens",
      "relevance_reason_code",
      "result_counts",
      "selected_group_order",
      "sufficiency_reason_code",
      "timings_ms",
    ],
    "response_diagnostics_invalid",
  );
  if (
    !Number.isInteger(diagnostics.api_processing_ms) ||
    diagnostics.api_processing_ms < 0 ||
    diagnostics.api_processing_ms > 86400000 ||
    typeof diagnostics.generation_retry !== "boolean"
  ) {
    fail("response_diagnostics_invalid");
  }
  const timings = exactObject(
    diagnostics.timings_ms,
    ["generation", "query_resolution", "response_build", "retrieval", "retrieval_detail", "scope"],
    "response_diagnostic_timings_invalid",
  );
  for (const [name, duration] of Object.entries(timings)) {
    if (name === "retrieval_detail") continue;
    if (!Number.isInteger(duration) || duration < 0 || duration > 86400000) {
      fail("response_diagnostic_timings_invalid");
    }
  }
  if (timings.retrieval_detail !== null) {
    const detail = exactObject(
      timings.retrieval_detail,
      ["fusion", "lexical_sql", "nomic", "reconstruction", "tokenization", "vector_sql"],
      "response_diagnostic_timings_invalid",
    );
    for (const duration of Object.values(detail)) {
      if (!Number.isInteger(duration) || duration < 0 || duration > 86400000) {
        fail("response_diagnostic_timings_invalid");
      }
    }
  }
  if (diagnostics.lane_states === null) {
    if (diagnostics.result_counts !== null) fail("response_diagnostic_retrieval_invalid");
  } else {
    const lanes = exactObject(
      diagnostics.lane_states,
      ["exact", "lexical", "vector"],
      "response_diagnostic_lanes_invalid",
    );
    if (Object.values(lanes).some((state) => !["pass", "not_applicable", "failed"].includes(state))) {
      fail("response_diagnostic_lanes_invalid");
    }
    const counts = exactObject(
      diagnostics.result_counts,
      ["authorized", "cited", "fused", "reconstructed"],
      "response_diagnostic_retrieval_invalid",
    );
    Object.values(counts).forEach((count) => nullableCount(count, "response_diagnostic_retrieval_invalid"));
    if (Object.values(counts).some((count) => count === null)) {
      fail("response_diagnostic_retrieval_invalid");
    }
  }
  nullableCount(diagnostics.nomic_query_tokens, "response_diagnostic_nomic_invalid");
  nullableCount(diagnostics.prompt_target_tokens, "response_diagnostic_prompt_target_invalid");
  const reasonCode = (value) =>
    value === null || (typeof value === "string" && /^[A-Z][A-Z0-9_]{0,95}$/.test(value));
  if (
    !reasonCode(diagnostics.relevance_reason_code) ||
    !reasonCode(diagnostics.sufficiency_reason_code)
  ) {
    fail("response_diagnostic_reason_invalid");
  }
  if (
    diagnostics.selected_group_order !== null &&
    (!Array.isArray(diagnostics.selected_group_order) ||
      diagnostics.selected_group_order.length > 6 ||
      new Set(diagnostics.selected_group_order).size !== diagnostics.selected_group_order.length ||
      diagnostics.selected_group_order.some(
        (value) => typeof value !== "string" || value.length < 1 || value.length > 1024,
      ))
  ) {
    fail("response_diagnostic_group_order_invalid");
  }
  if (diagnostics.gemma_tokens !== null) {
    const tokens = exactObject(
      diagnostics.gemma_tokens,
      ["completion", "prompt", "total"],
      "response_diagnostic_gemma_invalid",
    );
    if (
      !Number.isInteger(tokens.prompt) || tokens.prompt < 1 ||
      !Number.isInteger(tokens.completion) || tokens.completion < 1 ||
      tokens.total !== tokens.prompt + tokens.completion
    ) {
      fail("response_diagnostic_gemma_invalid");
    }
  }
  if (diagnostics.context_tokens !== null) {
    const context = exactObject(
      diagnostics.context_tokens,
      ["limit", "remaining", "used"],
      "response_diagnostic_context_invalid",
    );
    if (
      !Number.isInteger(context.limit) || context.limit < 1 ||
      !Number.isInteger(context.used) || context.used < 0 ||
      !Number.isInteger(context.remaining) || context.remaining < 0 ||
      context.used + context.remaining !== context.limit
    ) {
      fail("response_diagnostic_context_invalid");
    }
  }
  return diagnostics;
}

export function validateChatResponse(value, request) {
  const root = exactObject(
    value,
    ["clarification", "context_budget", "conversation_id", "diagnostics", "error", "request_id", "schema", "segments", "sources", "status", "turn_id"],
    "response_fields_invalid",
  );
  if (
    root.schema !== RESPONSE_SCHEMA ||
    !STATUSES.has(root.status) ||
    root.conversation_id !== request.conversation_id ||
    root.turn_id !== request.turn_id
  ) {
    fail("response_identity_invalid");
  }
  identity(root.request_id, "response_request_id_invalid");
  validateDiagnostics(root.diagnostics);
  if (root.status === "answered") {
    validateContextBudget(root.context_budget);
    const citationIds = validateSources(root.sources);
    if (!Array.isArray(root.segments) || root.segments.length < 1 || root.segments.length > 64) {
      fail("response_segments_invalid");
    }
    for (const value of root.segments) {
      const segment = exactObject(value, ["citation_ids", "text"], "response_segment_invalid");
      boundedText(segment.text, 65536, "response_segment_invalid");
      if (
        !Array.isArray(segment.citation_ids) ||
        segment.citation_ids.length < 1 ||
        !unique(segment.citation_ids) ||
        segment.citation_ids.some((citationId) => !citationIds.has(citationId))
      ) {
        fail("response_segment_citations_invalid");
      }
    }
    if (
      root.clarification !== null ||
      root.error !== null
    ) {
      fail("response_answer_invalid");
    }
  } else if (root.status === "clarification-required") {
    boundedText(root.clarification, 2048, "response_clarification_invalid");
    if (root.error !== null || root.context_budget !== null || root.segments.length || root.sources.length) {
      fail("response_status_fields_invalid");
    }
  } else {
    const error = exactObject(root.error, ["code", "message"], "response_error_invalid");
    if (!ERROR_CODE.test(error.code)) {
      fail("response_error_invalid");
    }
    boundedText(error.message, 2048, "response_error_invalid");
    if (root.clarification !== null || root.context_budget !== null || root.segments.length || root.sources.length) {
      fail("response_status_fields_invalid");
    }
  }
  return root;
}

export function validateTransportError(value) {
  const root = exactObject(value, ["error", "request_id", "schema"], "transport_error_invalid");
  const error = exactObject(root.error, ["code", "message"], "transport_error_invalid");
  if (root.schema !== TRANSPORT_ERROR_SCHEMA || !ERROR_CODE.test(error.code)) {
    fail("transport_error_invalid");
  }
  identity(root.request_id, "transport_error_invalid");
  boundedText(error.message, 2048, "transport_error_invalid");
  return root;
}

export function responseDisplayText(response) {
  if (response.status === "answered") {
    return response.segments.map((segment) => segment.text).join(" ");
  }
  if (response.status === "clarification-required") {
    return response.clarification;
  }
  return response.error.message;
}

export function buildDocumentViewRequest(sourceId, sectionOffset = 0, sectionLimit = 4) {
  identity(sourceId, "document_source_id_invalid");
  if (
    !Number.isInteger(sectionOffset) || sectionOffset < 0 || sectionOffset > 100000 ||
    !Number.isInteger(sectionLimit) || sectionLimit < 1 || sectionLimit > 10
  ) {
    fail("document_page_invalid");
  }
  return {
    schema: DOCUMENT_REQUEST_SCHEMA,
    section_limit: sectionLimit,
    section_offset: sectionOffset,
    source_id: sourceId,
  };
}

export function validateDocumentViewResponse(value, sourceId) {
  const root = exactObject(
    value,
    ["complete", "next_section_offset", "schema", "sections", "source", "total_sections"],
    "document_response_fields_invalid",
  );
  if (
    root.schema !== DOCUMENT_RESPONSE_SCHEMA ||
    typeof root.complete !== "boolean" ||
    !Number.isInteger(root.total_sections) || root.total_sections < 1 ||
    (root.next_section_offset !== null &&
      (!Number.isInteger(root.next_section_offset) || root.next_section_offset < 1)) ||
    !Array.isArray(root.sections)
  ) {
    fail("document_response_invalid");
  }
  const source = exactObject(
    root.source,
    ["display_name", "document_class", "document_identifier", "document_key", "page_count", "source_id"],
    "document_source_invalid",
  );
  if (
    identity(source.source_id, "document_source_invalid") !== sourceId ||
    !CLASS_ID.test(source.document_class) || !DOCUMENT_KEY.test(source.document_key) ||
    !Number.isInteger(source.page_count) || source.page_count < 1 || source.page_count > 1000000
  ) {
    fail("document_source_invalid");
  }
  boundedText(source.display_name, 512, "document_source_invalid");
  if (source.document_identifier !== null) {
    boundedText(source.document_identifier, 512, "document_source_invalid");
  }
  for (const section of root.sections) {
    exactObject(section, ["heading", "ordinal", "units"], "document_section_invalid");
    boundedText(section.heading, 2048, "document_section_invalid");
    if (!Number.isInteger(section.ordinal) || section.ordinal < 0 || !Array.isArray(section.units) || !section.units.length) {
      fail("document_section_invalid");
    }
    for (const unit of section.units) {
      exactObject(unit, ["kind", "page_end", "page_start", "structural_path", "text"], "document_unit_invalid");
      if (!DOCUMENT_UNIT_KINDS.has(unit.kind)) {
        fail("document_unit_invalid");
      }
      boundedText(unit.text, 262144, "document_unit_invalid");
      if (
        !Number.isInteger(unit.page_start) || !Number.isInteger(unit.page_end) ||
        unit.page_start < 1 || unit.page_end < unit.page_start ||
        unit.page_end > source.page_count ||
        !Array.isArray(unit.structural_path) ||
        unit.structural_path.some((item) => typeof item !== "string" || !item.trim())
      ) {
        fail("document_unit_invalid");
      }
    }
  }
  if (
    root.sections.length > root.total_sections ||
    (root.complete && root.next_section_offset !== null) ||
    (!root.complete && root.next_section_offset === null)
  ) {
    fail("document_response_invalid");
  }
  return root;
}
