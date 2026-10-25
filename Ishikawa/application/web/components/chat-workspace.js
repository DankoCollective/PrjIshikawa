"use client";

import { useEffect, useRef, useState } from "react";

import PresentationMarkdown from "./presentation-markdown.js";

import {
  MAXIMUM_QUESTION_CHARACTERS,
  buildDocumentViewRequest,
  buildChatRequest,
  createOpaqueIdentity,
  responseDisplayText,
  stabilizeChatSourceLabels,
  validateChatResponse,
  validateDocumentViewResponse,
  validateTransportError,
} from "../lib/chat-contract.mjs";

const STORAGE_KEY = "ishikawa.session-chats.v1.3";
const THEME_KEY = "ishikawa.theme";
const DEFAULT_CHAT_LABEL = "New chat";

class SafeRequestError extends Error {}

function assistantLabel(status) {
  const labels = {
    answered: "Answer",
    "clarification-required": "Clarification needed",
    "context-limit": "Context limit",
    "insufficient-evidence": "Not enough evidence",
    "internal-error": "Unable to answer",
    "out-of-scope": "Outside supported scope",
    "security-rejected": "Request rejected",
    "temporarily-unavailable": "Temporarily unavailable",
  };
  return labels[status] ?? "Response";
}

function pageCountLabel(pageCount) {
  return `${pageCount.toLocaleString("en-US")} ${pageCount === 1 ? "page" : "pages"}`;
}

function createConversation(label = DEFAULT_CHAT_LABEL) {
  const now = Date.now();
  return {
    contextBudget: null,
    createdAt: now,
    id: createOpaqueIdentity(),
    label,
    messages: [],
    selectedTurnId: null,
    updatedAt: now,
  };
}

function restoreSession() {
  try {
    const parsed = JSON.parse(sessionStorage.getItem(STORAGE_KEY) ?? "null");
    if (
      parsed?.schema !== "ishikawa.session-chats.v1.3" ||
      !Array.isArray(parsed.conversations) ||
      parsed.conversations.length < 1 ||
      typeof parsed.activeId !== "string"
    ) {
      return null;
    }
    const active = parsed.conversations.find((item) => item?.id === parsed.activeId);
    return active ? { activeId: parsed.activeId, conversations: parsed.conversations } : null;
  } catch {
    return null;
  }
}

function citedLabels(segment, sources) {
  const labels = new Set();
  for (const source of sources) {
    for (const excerpt of source.excerpts) {
      if (segment.citation_ids.includes(excerpt.citation_id)) {
        labels.add(
          source.document_identifier
            ? `${source.source_label} · ${source.document_identifier}`
            : source.source_label,
        );
      }
    }
  }
  return [...labels];
}

function groupStructuralExcerpts(excerpts) {
  const groups = [];
  const byHeading = new Map();
  for (const excerpt of excerpts) {
    const heading = excerpt.structural_path[0] ?? "Cited content";
    let group = byHeading.get(heading);
    if (!group) {
      group = { excerpts: [], heading };
      groups.push(group);
      byHeading.set(heading, group);
    }
    group.excerpts.push(excerpt);
  }
  return groups;
}

function SourceCard({ onViewDocument, source }) {
  const identifier = source.document_identifier ?? source.document_key;
  const groups = groupStructuralExcerpts(source.excerpts);
  return (
    <details className="source-card">
      <summary>
        <span className="source-label">{source.source_label}</span>
        <span className="source-heading">
          <strong>{identifier}</strong>
          <span>{source.display_name}</span>
          <small>{pageCountLabel(source.page_count)}</small>
        </span>
        <span aria-hidden="true" className="source-chevron">⌄</span>
      </summary>
      <div className="source-meta">
        <span>{source.document_class.replaceAll("_", " ")}</span>
        <span>Tag: {source.document_key}</span>
      </div>
      <div className="source-actions">
        {source.has_additional_sections ? <span>Additional sections available</span> : <span>Full document available</span>}
        <button onClick={() => onViewDocument(source)} type="button">View full document</button>
      </div>
      {groups.map((group) => (
        <article className="document-section" key={group.heading}>
          <h4>{group.heading}</h4>
          <div className="document-section-text">
            {group.excerpts.map((excerpt) => (
              <p key={excerpt.citation_id}>{excerpt.excerpt}</p>
            ))}
          </div>
          <footer>
            Pages {[...new Set(group.excerpts.flatMap((item) => (
              item.page_start === item.page_end
                ? [item.page_start]
                : [`${item.page_start}–${item.page_end}`]
            )))].join(", ")}
          </footer>
        </article>
      ))}
    </details>
  );
}

function ReconstructedUnits({ units }) {
  const blocks = [];
  for (const unit of units) {
    const collection = unit.kind === "list_item"
      ? "list"
      : unit.kind === "procedure_step"
        ? "procedure"
        : null;
    const previous = blocks.at(-1);
    if (collection && previous?.kind === collection) {
      previous.units.push(unit);
    } else {
      blocks.push({ kind: collection ?? unit.kind, units: [unit] });
    }
  }
  return blocks.map((block, blockIndex) => {
    if (block.kind === "list" || block.kind === "procedure") {
      const List = block.kind === "list" ? "ul" : "ol";
      return (
        <List className={`unit-${block.kind}`} key={`${block.kind}-${blockIndex}`}>
          {block.units.map((unit, unitIndex) => (
            <li key={`${unit.page_start}-${unitIndex}`}>{unit.text}</li>
          ))}
        </List>
      );
    }
    const unit = block.units[0];
    return (
      <p className={`unit-${unit.kind}`} key={`${unit.kind}-${blockIndex}`}>{unit.text}</p>
    );
  });
}

function DocumentViewer({ onLoadMore, onToggle, viewer }) {
  if (!viewer) return null;
  return (
    <section className="document-viewer">
      <div className="document-viewer-heading">
        <span>
          <small>Reconstructed active document</small>
          <strong>{viewer.source?.document_identifier ?? viewer.source?.document_key ?? "Document"}</strong>
          <span>{viewer.source?.display_name ?? ""}</span>
          {viewer.source?.page_count ? <span>{pageCountLabel(viewer.source.page_count)}</span> : null}
        </span>
        <button onClick={onToggle} type="button">{viewer.open ? "Collapse" : "Open"}</button>
      </div>
      {viewer.open ? (
        <div className="document-viewer-body">
          {viewer.error ? <p className="viewer-error">{viewer.error}</p> : null}
          {viewer.sections.map((section) => (
            <section className="reconstructed-section" key={`${section.ordinal}-${section.heading}`}>
              <h3>{section.heading}</h3>
              <ReconstructedUnits units={section.units} />
              <footer>
                Pages {[...new Set(section.units.flatMap((unit) => (
                  unit.page_start === unit.page_end
                    ? [unit.page_start]
                    : [`${unit.page_start}–${unit.page_end}`]
                )))].join(", ")}
              </footer>
            </section>
          ))}
          {!viewer.complete ? (
            <button disabled={viewer.loading} onClick={onLoadMore} type="button">
              {viewer.loading ? "Loading…" : "Load more sections"}
            </button>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}

function DiagnosticValue({ label, value }) {
  return (
    <div>
      <dt>{label}</dt>
      <dd>{value ?? "Not reached"}</dd>
    </div>
  );
}

function DiagnosticPanel({ message }) {
  if (!message) {
    return (
      <section className="diagnostic-panel">
        <strong>Developer diagnostics</strong>
        <p>Select a completed question or response to view its diagnostics.</p>
      </section>
    );
  }
  const diagnostics = message.diagnostics;
  if (!diagnostics) {
    return (
      <section className="diagnostic-panel">
        <strong>Developer diagnostics</strong>
        <p>Diagnostics are unavailable for this response.</p>
      </section>
    );
  }
  if (!Number.isInteger(diagnostics.api_processing_ms)) {
    return (
      <section className="diagnostic-panel">
        <div className="diagnostic-heading">
          <strong>Developer diagnostics</strong>
          <span>{message.status}</span>
        </div>
        <dl>
          <DiagnosticValue label="Request ID" value={message.id} />
          <DiagnosticValue label="Turn ID" value={message.turnId} />
          <DiagnosticValue label="Browser round trip" value={`${diagnostics.browser_round_trip_ms} ms`} />
          <DiagnosticValue label="API processing" value="No validated response" />
        </dl>
      </section>
    );
  }
  const timings = diagnostics.timings_ms ?? {};
  const retrievalDetail = timings.retrieval_detail ?? {};
  const lanes = diagnostics.lane_states ?? {};
  const counts = diagnostics.result_counts ?? {};
  const gemma = diagnostics.gemma_tokens ?? {};
  const context = diagnostics.context_tokens ?? {};
  return (
    <section className="diagnostic-panel">
      <div className="diagnostic-heading">
        <strong>Developer diagnostics</strong>
        <span>{message.status}</span>
      </div>
      <dl>
        <DiagnosticValue label="Request ID" value={message.id} />
        <DiagnosticValue label="Turn ID" value={message.turnId} />
        <DiagnosticValue label="Browser round trip" value={`${diagnostics.browser_round_trip_ms} ms`} />
        <DiagnosticValue label="API processing" value={`${diagnostics.api_processing_ms} ms`} />
        <DiagnosticValue label="Scope" value={`${timings.scope ?? 0} ms`} />
        <DiagnosticValue label="Query resolution" value={`${timings.query_resolution ?? 0} ms`} />
        <DiagnosticValue label="Combined retrieval" value={`${timings.retrieval ?? 0} ms`} />
        <DiagnosticValue label="Nomic embedding" value={`${retrievalDetail.nomic ?? 0} ms`} />
        <DiagnosticValue label="Lexical SQL" value={`${retrievalDetail.lexical_sql ?? 0} ms`} />
        <DiagnosticValue label="Vector SQL" value={`${retrievalDetail.vector_sql ?? 0} ms`} />
        <DiagnosticValue label="Fusion and ranking" value={`${retrievalDetail.fusion ?? 0} ms`} />
        <DiagnosticValue label="Evidence reconstruction" value={`${retrievalDetail.reconstruction ?? 0} ms`} />
        <DiagnosticValue label="Prompt tokenization" value={`${retrievalDetail.tokenization ?? 0} ms`} />
        <DiagnosticValue label="Generation" value={`${timings.generation ?? 0} ms`} />
        <DiagnosticValue label="Response build" value={`${timings.response_build ?? 0} ms`} />
        <DiagnosticValue label="Exact lane" value={lanes.exact} />
        <DiagnosticValue label="Lexical lane" value={lanes.lexical} />
        <DiagnosticValue label="Vector lane" value={lanes.vector} />
        <DiagnosticValue label="Fused results" value={counts.fused} />
        <DiagnosticValue label="Authorized results" value={counts.authorized} />
        <DiagnosticValue label="Reconstructed units" value={counts.reconstructed} />
        <DiagnosticValue label="Packed citations" value={counts.cited} />
        <DiagnosticValue label="Relevance decision" value={diagnostics.relevance_reason_code} />
        <DiagnosticValue label="Sufficiency decision" value={diagnostics.sufficiency_reason_code} />
        <DiagnosticValue
          label="Selected group order"
          value={diagnostics.selected_group_order?.join(" → ")}
        />
        <DiagnosticValue label="Nomic query tokens" value={diagnostics.nomic_query_tokens} />
        <DiagnosticValue label="Prompt target" value={diagnostics.prompt_target_tokens} />
        <DiagnosticValue label="Gemma prompt tokens" value={gemma.prompt} />
        <DiagnosticValue label="Gemma completion tokens" value={gemma.completion} />
        <DiagnosticValue label="Gemma total tokens" value={gemma.total} />
        <DiagnosticValue label="Context used" value={context.used} />
        <DiagnosticValue label="Context remaining" value={context.remaining} />
        <DiagnosticValue label="Context limit" value={context.limit} />
        <DiagnosticValue label="Generation retry" value={diagnostics.generation_retry ? "Yes" : "No"} />
      </dl>
    </section>
  );
}

function Message({ message, onSelect, onViewerLoadMore, onViewerToggle, selected, viewer }) {
  if (message.role === "user") {
    return (
      <article
        className={`operator-message ${selected ? "selected-turn" : ""}`}
        onClick={onSelect}
        onKeyDown={(event) => {
          if (event.target === event.currentTarget && ["Enter", " "].includes(event.key)) {
            event.preventDefault();
            onSelect();
          }
        }}
        role="button"
        tabIndex={0}
      >
        <small>You</small>
        <p>{message.content}</p>
      </article>
    );
  }
  return (
    <article
      className={`assistant-message response-${message.status} ${selected ? "selected-turn" : ""}`}
      onClick={onSelect}
      onKeyDown={(event) => {
        if (event.target === event.currentTarget && ["Enter", " "].includes(event.key)) {
          event.preventDefault();
          onSelect();
        }
      }}
      role="button"
      tabIndex={0}
    >
      <div className="response-heading">
        <span className="response-glyph" aria-hidden="true">▤</span>
        <span>
          <small>Ishikawa response</small>
          <strong>{assistantLabel(message.status)}</strong>
        </span>
      </div>
      <div className="response-body">
        {message.segments?.length ? message.segments.map((segment, index) => (
          <p className="answer-segment" key={`${message.id}-segment-${index}`}>
            {segment.text}{" "}
            <span className="segment-citations">{citedLabels(segment, message.sources).join(", ")}</span>
          </p>
        )) : <p>{message.content}</p>}
        <DocumentViewer
          onLoadMore={onViewerLoadMore}
          onToggle={onViewerToggle}
          viewer={viewer}
        />
      </div>
    </article>
  );
}

function readFailure(payload) {
  try {
    return validateTransportError(payload).error.message;
  } catch {
    if (payload?.schema === "ishikawa.web-error.v1" && typeof payload.message === "string") {
      return payload.message;
    }
    return "The request could not be completed.";
  }
}

function ServiceRow({ label, status }) {
  const available = status === "available";
  return (
    <li>
      <span aria-hidden="true" className={`event-dot ${available ? "success" : "warning"}`} />
      <span><strong>{label}</strong><small>{available ? "Available" : "Unavailable"}</small></span>
    </li>
  );
}

export default function ChatWorkspace({ productConfiguration, productName }) {
  const [conversations, setConversations] = useState([]);
  const [activeId, setActiveId] = useState(null);
  const [draft, setDraft] = useState("");
  const [editingId, setEditingId] = useState(null);
  const [editingLabel, setEditingLabel] = useState("");
  const [pending, setPending] = useState(false);
  const [restored, setRestored] = useState(false);
  const [theme, setTheme] = useState("light");
  const [diagnosticsOpen, setDiagnosticsOpen] = useState(false);
  const [dependencies, setDependencies] = useState({ gemma: "unavailable", nomic: "unavailable" });
  const [documentViewers, setDocumentViewers] = useState({});
  const composer = useRef(null);
  const transcriptEnd = useRef(null);

  const activeConversation = conversations.find((item) => item.id === activeId) ?? null;
  const messages = activeConversation?.messages ?? [];
  const selectedTurnId = activeConversation?.selectedTurnId ?? null;
  const selectedResponse = messages.find(
    (item) => item.role === "assistant" && item.turnId === selectedTurnId,
  ) ?? null;
  const turnSources = selectedResponse?.sources ?? [];

  useEffect(() => {
    const saved = restoreSession();
    if (saved) {
      setConversations(saved.conversations);
      setActiveId(saved.activeId);
    } else {
      const conversation = createConversation();
      setConversations([conversation]);
      setActiveId(conversation.id);
    }
    setTheme(document.documentElement.dataset.theme === "dark" ? "dark" : "light");
    setRestored(true);
  }, []);

  useEffect(() => {
    if (!restored || conversations.length < 1 || !activeId) {
      return;
    }
    try {
      sessionStorage.setItem(
        STORAGE_KEY,
        JSON.stringify({ activeId, conversations, schema: "ishikawa.session-chats.v1.3" }),
      );
    } catch {
      // Keep the session usable in memory if browser storage is unavailable.
    }
  }, [activeId, conversations, restored]);

  useEffect(() => {
    let stopped = false;
    async function refreshDependencies() {
      try {
        const response = await fetch("/api/dependencies", { cache: "no-store" });
        const value = await response.json();
        if (
          !stopped &&
          value?.schema === "ishikawa.web-dependency-health.v1" &&
          ["available", "unavailable"].includes(value.gemma) &&
          ["available", "unavailable"].includes(value.nomic)
        ) {
          setDependencies({ gemma: value.gemma, nomic: value.nomic });
        }
      } catch {
        if (!stopped) {
          setDependencies({ gemma: "unavailable", nomic: "unavailable" });
        }
      }
    }
    refreshDependencies();
    const timer = window.setInterval(refreshDependencies, 15000);
    return () => {
      stopped = true;
      window.clearInterval(timer);
    };
  }, []);

  useEffect(() => {
    transcriptEnd.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [messages, pending]);

  const remaining = MAXIMUM_QUESTION_CHARACTERS - draft.length;
  const canSubmit = Boolean(activeConversation && draft.trim() && remaining >= 0 && !pending);

  function updateConversation(conversationId, updater) {
    setConversations((current) => current.map((conversation) => (
      conversation.id === conversationId
        ? { ...updater(conversation), updatedAt: Date.now() }
        : conversation
    )));
  }

  function focusComposer() {
    window.requestAnimationFrame(() => composer.current?.focus());
  }

  function startConversation() {
    if (pending) {
      return;
    }
    const conversation = createConversation();
    setConversations((current) => [conversation, ...current]);
    setActiveId(conversation.id);
    setDraft("");
    focusComposer();
  }

  function selectTurn(turnId) {
    if (!activeConversation || !turnId) return;
    updateConversation(activeConversation.id, (conversation) => ({
      ...conversation,
      selectedTurnId: turnId,
    }));
  }

  async function loadDocument(source, turnId, sectionOffset = 0) {
    if (!activeConversation) return;
    const viewerKey = `${activeConversation.id}:${turnId}`;
    const existing = documentViewers[viewerKey];
    if (sectionOffset === 0 && existing?.source?.source_id === source.source_id) {
      setDocumentViewers((current) => ({
        ...current,
        [viewerKey]: { ...existing, open: !existing.open },
      }));
      return;
    }
    setDocumentViewers((current) => ({
      ...current,
      [viewerKey]: {
        ...(sectionOffset > 0 && existing ? existing : { sections: [] }),
        complete: false,
        error: null,
        loading: true,
        open: true,
        source,
      },
    }));
    try {
      const request = buildDocumentViewRequest(source.source_id, sectionOffset, 4);
      const response = await fetch("/api/v1/document", {
        body: JSON.stringify(request),
        headers: { "Content-Type": "application/json" },
        method: "POST",
      });
      const payload = await response.json();
      if (!response.ok) throw new SafeRequestError("The exact active document version is unavailable.");
      const document = validateDocumentViewResponse(payload, source.source_id);
      setDocumentViewers((current) => {
        const previous = current[viewerKey];
        if (previous?.source?.source_id !== source.source_id) return current;
        return {
          ...current,
          [viewerKey]: {
            complete: document.complete,
            error: null,
            loading: false,
            nextOffset: document.next_section_offset,
            open: true,
            sections: sectionOffset === 0
              ? document.sections
              : [...previous.sections, ...document.sections],
            source: document.source,
          },
        };
      });
    } catch (error) {
      setDocumentViewers((current) => ({
        ...current,
        [viewerKey]: {
          ...(current[viewerKey] ?? { sections: [], source }),
          error: error instanceof SafeRequestError ? error.message : "Document viewing is temporarily unavailable.",
          loading: false,
          open: true,
        },
      }));
    }
  }

  function useStarter(starter) {
    if (pending) {
      return;
    }
    setDraft(starter);
    focusComposer();
  }

  function updateTheme(nextTheme) {
    document.documentElement.dataset.theme = nextTheme;
    try {
      localStorage.setItem(THEME_KEY, nextTheme);
    } catch {
      // The theme still applies to this page when local storage is unavailable.
    }
    setTheme(nextTheme);
  }

  function commitRename(conversationId) {
    const label = editingLabel.trim();
    if (label) {
      updateConversation(conversationId, (conversation) => ({
        ...conversation,
        label: label.slice(0, 80),
      }));
    }
    setEditingId(null);
    setEditingLabel("");
  }

  async function submit(event) {
    event?.preventDefault();
    if (!canSubmit || !activeConversation) {
      return;
    }
    const conversationId = activeConversation.id;
    const question = draft.trim();
    const turnId = createOpaqueIdentity();
    let request;
    try {
      request = buildChatRequest({
        conversationId,
        message: question,
        priorMessages: activeConversation.messages,
        turnId,
      });
    } catch {
      return;
    }
    const userMessage = {
      content: question,
      historyTurnId: turnId,
      id: turnId,
      role: "user",
      sources: [],
      turnId,
    };
    setDraft("");
    updateConversation(conversationId, (conversation) => ({
      ...conversation,
      label: conversation.messages.length === 0 && conversation.label === DEFAULT_CHAT_LABEL
        ? question.slice(0, 48)
        : conversation.label,
      messages: [...conversation.messages, userMessage],
      selectedTurnId: turnId,
    }));
    setPending(true);
    const requestStarted = globalThis.performance?.now() ?? Date.now();
    try {
      const result = await fetch("/api/v1/chat", {
        body: JSON.stringify(request),
        headers: { "Content-Type": "application/json" },
        method: "POST",
      });
      const payload = await result.json();
      if (!result.ok) {
        throw new SafeRequestError(readFailure(payload));
      }
      const response = validateChatResponse(payload, request);
      const browserRoundTrip = Math.max(
        0,
        Math.round((globalThis.performance?.now() ?? Date.now()) - requestStarted),
      );
      const stableSources = stabilizeChatSourceLabels(activeConversation.messages, response.sources);
      const assistantMessage = {
        segments: response.segments,
        content: responseDisplayText(response),
        diagnostics: {
          ...response.diagnostics,
          browser_round_trip_ms: browserRoundTrip,
        },
        historyTurnId: createOpaqueIdentity(),
        id: response.request_id,
        role: "assistant",
        sources: stableSources,
        status: response.status,
        turnId: response.turn_id,
      };
      updateConversation(conversationId, (conversation) => ({
        ...conversation,
        contextBudget: response.context_budget ?? conversation.contextBudget,
        messages: [...conversation.messages, assistantMessage],
        selectedTurnId: response.turn_id,
      }));
    } catch (error) {
      const content = error instanceof SafeRequestError && error.message
        ? error.message
        : "The request could not be completed.";
      updateConversation(conversationId, (conversation) => ({
        ...conversation,
        messages: [
          ...conversation.messages,
          {
            segments: [],
            content,
            diagnostics: {
              browser_round_trip_ms: Math.max(
                0,
                Math.round((globalThis.performance?.now() ?? Date.now()) - requestStarted),
              ),
            },
            historyTurnId: createOpaqueIdentity(),
            id: createOpaqueIdentity(),
            role: "assistant",
            sources: [],
            status: "temporarily-unavailable",
            turnId,
          },
        ],
      }));
    } finally {
      setPending(false);
      focusComposer();
    }
  }

  const budget = activeConversation?.contextBudget;
  const budgetUsedPercent = budget
    ? Math.min(100, Math.max(0, (budget.tokens_used / budget.token_limit) * 100))
    : 0;

  return (
    <div className="app-frame">
      <header className="app-header">
        <div className="brand-block" aria-label={productName}>
          <span className="brand-mark" aria-hidden="true">I</span>
          <span>
            <strong>{productName}</strong>
            <small>{productConfiguration.tagline}</small>
          </span>
        </div>

        <div className="workspace-header-center">
          <span className="workspace-chip"><span aria-hidden="true">▤</span> Knowledge chat</span>
          <span className="session-chip">Session only</span>
        </div>

        <div className="header-actions">
          <button
            aria-label={`${diagnosticsOpen ? "Hide" : "Show"} developer diagnostics`}
            aria-pressed={diagnosticsOpen}
            className={`icon-button ${diagnosticsOpen ? "active" : ""}`}
            onClick={() => setDiagnosticsOpen((current) => !current)}
            title="Developer diagnostics"
            type="button"
          >
            ◴
          </button>
          <button
            aria-label={`Switch to ${theme === "light" ? "dark" : "light"} theme`}
            className="icon-button"
            onClick={() => updateTheme(theme === "light" ? "dark" : "light")}
            type="button"
          >
            {theme === "light" ? "☾" : "☀"}
          </button>
        </div>
      </header>

      <aside aria-label="Session navigation" className="left-rail">
        <button className="new-chat-button" disabled={pending} onClick={startConversation} type="button">
          <span aria-hidden="true">＋</span> New chat
        </button>

        <section className="rail-section session-section">
          <p className="eyebrow">This session</p>
          <div className="chat-list">
            {conversations.map((conversation) => (
              <article className={`chat-card ${conversation.id === activeId ? "active" : ""}`} key={conversation.id}>
                {editingId === conversation.id ? (
                  <input
                    aria-label="Chat name"
                    autoFocus
                    maxLength={80}
                    onBlur={() => commitRename(conversation.id)}
                    onChange={(event) => setEditingLabel(event.target.value)}
                    onKeyDown={(event) => {
                      if (event.key === "Enter") commitRename(conversation.id);
                      if (event.key === "Escape") setEditingId(null);
                    }}
                    value={editingLabel}
                  />
                ) : (
                  <button
                    className="chat-select"
                    disabled={pending}
                    onClick={() => setActiveId(conversation.id)}
                    type="button"
                  >
                    <span className="session-icon" aria-hidden="true">◇</span>
                    <span className="session-copy">
                      <strong>{conversation.label}</strong>
                      <small>{conversation.messages.filter((item) => item.role === "user").length} questions</small>
                    </span>
                  </button>
                )}
                <button
                  aria-label={`Rename ${conversation.label}`}
                  className="rename-chat"
                  disabled={pending}
                  onClick={() => {
                    setEditingId(conversation.id);
                    setEditingLabel(conversation.label);
                  }}
                  type="button"
                >Rename</button>
              </article>
            ))}
          </div>
        </section>

        {productConfiguration.quickQuestions.length ? (
          <section className="rail-section quick-section">
            <p className="eyebrow">Quick questions</p>
            <div className="quick-list">
              {productConfiguration.quickQuestions.map((starter, index) => (
                <button disabled={pending} key={starter} onClick={() => useStarter(starter)} type="button">
                  <span className="quick-icon" aria-hidden="true">{["◇", "▤", "✓"][index % 3]}</span>
                  <span><strong>{starter}</strong></span>
                </button>
              ))}
            </div>
          </section>
        ) : null}

      </aside>

      <main className="workspace">
        <section className="chat-workspace">
          <div className="conversation-scroll">
            {messages.length === 0 ? (
              <div className="welcome-copy">
                {productConfiguration.emptyChat.blocks.map((block, index) => (
                  <PresentationMarkdown block={block} key={`${block.type}-${index}`} />
                ))}
              </div>
            ) : (
              <section aria-live="polite" className="transcript">
                {messages.map((message) => {
                  const viewerKey = `${activeConversation.id}:${message.turnId}`;
                  const viewer = message.role === "assistant"
                    ? documentViewers[viewerKey]
                    : null;
                  return (
                    <Message
                      key={message.id}
                      message={message}
                      onSelect={() => selectTurn(message.turnId)}
                      onViewerLoadMore={() => {
                        if (viewer?.source && viewer.nextOffset !== null) {
                          loadDocument(viewer.source, message.turnId, viewer.nextOffset);
                        }
                      }}
                      onViewerToggle={() => setDocumentViewers((current) => ({
                        ...current,
                        [viewerKey]: { ...current[viewerKey], open: !current[viewerKey]?.open },
                      }))}
                      selected={message.turnId === selectedTurnId}
                      viewer={viewer}
                    />
                  );
                })}
                {pending ? (
                  <div aria-label="Searching documents" className="thinking" role="status">
                    <span /><span /><span /><small>Searching documents…</small>
                  </div>
                ) : null}
              </section>
            )}
            <div ref={transcriptEnd} />
          </div>

          <footer className="composer-region">
            <div className="token-budget-meter" role="status">
              <div className="token-budget-copy">
                <span>Context budget</span>
                <strong>
                  {budget
                    ? `${budget.tokens_remaining.toLocaleString("en-US")} of ${budget.token_limit.toLocaleString("en-US")} tokens remaining`
                    : "Measured after the first answer"}
                </strong>
              </div>
              <div
                aria-label={budget ? `${Math.round(budgetUsedPercent)} percent of context used` : "Context use not yet measured"}
                aria-valuemax={100}
                aria-valuemin={0}
                aria-valuenow={Math.round(budgetUsedPercent)}
                className="token-budget-track"
                role="progressbar"
              >
                <span style={{ width: `${budgetUsedPercent}%` }} />
              </div>
            </div>
            <form className="composer" onSubmit={submit}>
              <label className="visually-hidden" htmlFor="message">Ask {productName} a question</label>
              <textarea
                id="message"
                maxLength={MAXIMUM_QUESTION_CHARACTERS}
                onChange={(event) => setDraft(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter" && !event.shiftKey) {
                    event.preventDefault();
                    submit(event);
                  }
                }}
                placeholder="Ask about an approved policy, regulation, code of conduct, or procedure…"
                ref={composer}
                rows={3}
                value={draft}
              />
              <div className="composer-footer">
                <span className={remaining < 256 ? "character-count warning" : "character-count"}>
                  {remaining.toLocaleString("en-US")} characters remaining · Enter to send · Shift+Enter for a new line
                </span>
                <button disabled={!canSubmit} type="submit">
                  <span>Ask</span><span aria-hidden="true">➤</span>
                </button>
              </div>
            </form>
            <p className="notice">{productConfiguration.footerNotice}</p>
            {diagnosticsOpen ? <DiagnosticPanel message={selectedResponse} /> : null}
          </footer>
        </section>
      </main>

      <aside aria-label="Citations and model connections" className="right-rail">
        <section className="context-card citation-card">
          <div className="section-heading">
            <span><strong>Citations</strong></span>
            <span className="count-badge">{turnSources.length}</span>
          </div>
          {turnSources.length ? (
            <div className="citation-list">
              {turnSources.map((source) => (
                <SourceCard
                  key={source.source_id}
                  onViewDocument={() => loadDocument(source, selectedTurnId, 0)}
                  source={source}
                />
              ))}
            </div>
          ) : (
            <p className="empty-rail">Select a question or response to view its citations.</p>
          )}
        </section>

        <section className="context-card service-card">
          <div className="section-heading">
            <span><strong>Model connections</strong></span>
          </div>
          <ol className="activity-list">
            <ServiceRow label="Gemma" status={dependencies.gemma} />
            <ServiceRow label="Nomic" status={dependencies.nomic} />
          </ol>
        </section>
      </aside>
    </div>
  );
}
