# Normalization and Structural Units

## Boundary

The v1 normalizer consumes only a checksum-accepted Poppler extraction
archive and its checksum-bound source manifest. The raw archive remains the
immutable evidence layer. Normalization creates a separate deterministic
canonical JSON layer; it never replaces or edits raw extraction output.

The implementation uses the Python standard library. It invokes no shell or
external program, contacts no service, reads no database, and calls no model.

## Canonicalization rules

The normalizer:

1. verifies the complete archive SHA-256 before reading it;
2. rejects links, devices, traversal, duplicate archive members, oversized
   files, unsafe source symlinks, non-finite geometry, and XML entity
   declarations;
3. verifies each bounding-box output against the accepted capture record;
4. orders physical lines top-to-bottom and same-row lines left-to-right;
5. orders words within a physical line left-to-right;
6. applies Unicode NFC and consistent single-space token joining;
7. joins wrapped lines only when geometry, path, and punctuation support one
   continuing unit;
8. preserves visible hyphens, punctuation, numbers, identifiers, list/step
   markers, and checkbox states;
9. records ordered transform-rule identifiers, source spans and geometry,
   input/output digests, and a stable identity for every normalized unit; and
10. verifies that every extracted source token belongs to exactly one primary
    normalized structural unit.

The current transform identity is `ishikawa-poppler-normalization-v1`.

## Structural units

The canonical unit kinds are:

- `heading` — Roman-numbered or typographically supported headings;
- `paragraph` — narrative material, including deterministic wrapped-line
  joins;
- `definition` — explicit `term means ...` forms and marked term/definition
  structures;
- `list_item` — one numbered or lettered item, including items that share one
  physical source line;
- `table` — a structured table authority containing ordered headers, atomic
  rows, header/value cells, spans, continuation flags, context, and anchors;
- `form_field` — one label/value association with geometry and anchors;
- `checkbox_group` — one field label with every adjacent option and an
  explicit Boolean state;
- `page_furniture` — raw retained recurring headers or footers separated from
  semantic content by geometry plus recurrence evidence.

Blank pages remain explicit page observations and do not receive invented
text units.

Every semantic unit carries its page range, structural path, normalized text,
raw source spans, geometry, deterministic references, rules, and digests.
The table and form structures are authoritative. Their text is a
deterministic inspection projection, not a replacement for their structured
fields.

## Furniture rule

Furniture requires both a comparable top/bottom page position and recurrence
on at least half of a document's eligible pages, with a minimum of two
occurrences. Page-number suffixes use one deterministic signature placeholder
while every original occurrence remains anchored and retained.

A document with only one nonblank page cannot establish recurrence, so the
normalizer does not suppress a possible header or footer merely because it
looks similar to another document. This deliberately favors retention over
guessing.

## Table and form behavior

A table requires at least three geometrically compatible rows and at least
three stable columns. The first row becomes ordered headers; every remaining
row remains atomic and carries header/value cell associations. The current
qualified fixture is a single-page table. Multi-page continuation remains a
later qualification case and is not inferred without evidence.

A form page is recognized from repeated geometric label/value or checkbox
patterns. Same-row labels and values are paired by horizontal interval.
Bounded following lines may supply a multiline value. Checkbox markers are
converted to explicit `selected: true|false` fields without dropping their
labels or source notation.

## Qualified synthetic result

The locally proven normalization of the accepted six-document, 27-page
capture produces:

```text
structural_units=230
headings=28
paragraphs=40
list_items=60
definitions=5
tables=1
form_fields=12
checkbox_groups=4
page_furniture=80
normalization_set_digest=86a31ba1ce7dea966273576553f09b244e7f3a3f9d4f7757812d04f9551f9e43
artifact_sha256=736d619ac5a7e10f768bdb8b8f3f117cb52231f8dc2f4d186d52d96c8bd41e28
```

Thirteen held-out normalization tests verify document/page inventory, all
required headings, the complete table, field/value pairs, checkbox states,
wrapped text, visible hyphens, inline step order, furniture separation,
anchors, digests, references, deterministic replay, checksum enforcement, and
symlink rejection. The existing 64 configuration, planning, reporting, and
writer tests also remain green.

This gate does not yet create retrieval chunks, measure Nomic tokens, call
Nomic, or write normalized content to PostgreSQL. Those remain later gates.
