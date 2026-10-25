# Injection Gate Contract

## Purpose and placement

Ishikawa keeps scope classification and prompt-injection defense as separate
gates. A mechanically valid user turn first receives the required Gemma scope
decision. Only `allow` continues to this deterministic scanner, and only a
scanner `pass` may continue to retrieval.

The same scanner also examines accepted conversation history before retrieval
and retrieved text before that text can enter answer-generation context. User,
conversation, and document text are always untrusted data.

## Initial deterministic ruleset

The versioned `builtin_v1` ruleset detects a narrow set of high-signal cases:

- hidden Unicode direction, formatting, or control characters;
- long base64-shaped payloads used for obfuscation;
- explicit attempts to override trusted instructions;
- system, developer, or administrator role impersonation;
- explicit requests to extract hidden prompts;
- explicit requests to disclose credentials or secrets; and
- requests to use a shell, terminal, filesystem, database, command, or script.

The scanner normalizes a copy of each field with Unicode NFKC before pattern
evaluation. Stored source text is not rewritten. The limits, ruleset name,
normalization form, rejection status, reason-code order, patterns, and special
checks are all bound into the injection-policy identity.

This scanner is defense in depth. It does not claim that signatures eliminate
prompt injection. Model isolation, typed prompt construction, no model tool
authority, strict response schemas, citation enforcement, and later
adversarial qualification remain independent controls.

## Result and operator visibility

A clean scan returns `pass` with no reason. A finding returns
`security_rejected`, one stable content-free reason code, the typed origin, and
a finding count. Detection details and source text are not included in routine
logs. The first slice fails the affected request closed; it never sends
suspicious text to retrieval or generation.

Script `53` accepted all seven reasons across current-question, conversation,
and retrieved-content origins using synthetic cases. It was local-only and did
not call Gemma, access PostgreSQL, contact a remote host, or retain case text.
