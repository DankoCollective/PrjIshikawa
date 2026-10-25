# Scope Classifier Contract

## Purpose

Every mechanically valid natural-language turn passes through the configured
local Gemma scope classifier before retrieval. The classifier decides whether
the question belongs in Ishikawa's professional and organizational knowledge
workflow. It does not answer the question, retrieve documents, evaluate
evidence sufficiency, or perform prompt-injection enforcement.

The three decisions are:

- `allow`: continue to the separate injection gate and then retrieval;
- `needs_clarification`: return the classifier's bounded clarification question
  without retrieval; and
- `out_of_scope`: return a safe out-of-scope result without retrieval.

## Versioned configuration

`config/templates/scope_profile.yaml` controls the served model, thinking and
temperature settings, maximum output, input limits, and decision-specific
reason-code allowlists. The validated canonical profile receives a SHA-256
domain identity. Changing the profile, trusted prompt, input schema, output
schema, reason codes, or limits creates a different identity and requires
classifier requalification.

The initial profile uses:

- `google/gemma-4-26B-A4B-it`;
- thinking disabled with publisher sampling defaults: temperature `1.0`,
  `top_p` `0.95`, and `top_k` `64`;
- a 128-token output ceiling;
- at most 16,384 characters in the current question;
- at most 12 accepted prior turns and 65,536 history characters; and
- at most 20 structured prior-source references.

These are classifier limits, not the larger grounded-answer reconstruction
budget.

## Trusted and untrusted boundaries

The system message contains only the trusted classifier instruction, allowed
scope, response schema, and reason-code allowlists. The current question,
accepted alternating conversation history, and structured source references
are serialized into one canonical JSON user message. Prompt-shaped text in
those fields remains data and cannot modify the trusted instruction.

A prior source reference contains only an opaque source identity, its
conversation-stable `Source N` label, and safe display name. The classifier
does not receive document paths, document bytes, retrieved excerpts, database
access, tools, or service credentials.

## Decisions and reasons

An `allow` decision uses one of:

- `organizational_policy`;
- `applicable_regulation`;
- `code_of_conduct`;
- `operating_procedure`;
- `professional_organizational_work`; or
- `prior_answer_or_source_followup`.

A `needs_clarification` decision uses `professional_context_unclear` or
`source_reference_unclear` and must include one trimmed, bounded clarification
question.

An `out_of_scope` decision uses `personal_or_recreational`,
`unrelated_general_knowledge`, or `non_organizational_request`.

The model output has exactly `decision`, `reason_code`, and `clarification`.
The reason must belong to the selected decision. Clarification is required
only for `needs_clarification` and must be null otherwise. An answer field,
unknown field, unknown reason, malformed content, or inconsistent
clarification fails closed. Content may be raw JSON or one isolated lower-case
`json` fence under the already-qualified compatibility rule.

## Separation from injection and retrieval

Scope and injection are separate gates. An organizational question containing
an attack can be in scope and still be rejected by the later injection gate.
An `allow` decision therefore means only that scope passed; it does not itself
authorize retrieval or answer generation.

Script `50` accepted the profile, deterministic request builder, typed source
references, strict decision validator, and failure paths locally. It did not
contact Gemma, PostgreSQL, Nomic, or a remote host. Script `51` measured that
exact checksum-bound request with the already-qualified deployed tokenizer in
a temporary network-disabled container: 526 prompt tokens and 654 tokens with
the response reserve. It did not call Gemma.

Script `52` is source-ready for one bounded live synthetic classification. It
uses the native standard-library HTTP transport, an operator-entered runtime
credential, the loopback Gemma endpoint, no retry, strict vLLM-envelope and
usage validation, and the frozen three-field decision validator. The expected
result for the accepted source-follow-up fixture is `allow` with
`prior_answer_or_source_followup` and no clarification. The protected result
is retained; questions and model text are excluded from the routine report.

Scripts `50` through `52` qualified the earlier zero-temperature request and
remain historical evidence for that identity. The operator subsequently chose
the publisher sampling profile (`temperature: 1.0`, `top_p: 0.95`,
`top_k: 64`) for every Gemma request. The resulting candidate scope-profile
identity is
`e6aba88193233aed29c015298fef7724dba22451c2769e8eb57e00cd225964b5`.
It requires a new numbered qualification before deployment acceptance.
