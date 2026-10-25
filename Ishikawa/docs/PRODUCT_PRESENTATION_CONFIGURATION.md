# Product Presentation Configuration

## Purpose

`config/product.yaml` controls Ishikawa's operator-facing product name and
selected Chat UI copy. It is deployment configuration: changing valid text
does not require rebuilding the Node image or changing retrieval behavior.

The stack validates the complete file before starting any component. Unknown
keys, invalid tokens, unsupported markup, duplicate quick questions, or limit
violations stop startup with a stable reason. The browser receives only a
canonical, validated presentation payload; it never parses YAML.

## Complete schema

Every listed key is required. No additional keys are accepted.

| Key | Type and limit | Meaning |
|---|---|---|
| `schema_version` | integer; exactly `2` | Selects this exact contract. |
| `display_name` | one line; 1–128 characters | Product name shown in the UI and page metadata. |
| `tagline` | one line; 1–256 characters | Text immediately beneath the product name in the upper-left rail. |
| `ui` | mapping | Contains all configurable Chat UI copy. |
| `ui.quick_questions` | list of 0–8 unique strings; each 1–512 characters | Left-rail quick-question buttons. An empty list removes that section. These buttons are not repeated in an empty chat. |
| `ui.footer_notice` | one line; 1–512 characters | Notice beneath the message composer. |
| `ui.empty_chat` | mapping | Owns the empty-chat presentation. |
| `ui.empty_chat.blocks` | list of 1–8 blocks; at most 8,192 Markdown characters in total | Ordered configurable empty-chat content. |
| `type` | `heading` or `body` | Selects the semantic block renderer. |
| `font` | `sans`, `serif`, or `mono` | Selects an installed, approved font stack. It does not download a font. |
| `size` | `small`, `medium`, `large`, or `display` | Selects an approved responsive size token. |
| `markdown` | multiline string; 1–4,096 characters per block | Restricted Markdown-compatible presentation text. |

Text fields reject leading or trailing whitespace and control characters.
Multiline YAML block scalars may end with YAML's normal final newline; the
validator removes only that final newline before producing the canonical
configuration.

## Supported formatting

The empty-chat `markdown` value supports this deliberately small subset:

- paragraphs separated by blank lines;
- preserved line breaks and explicit `<br>` or `<br />` breaks;
- `**bold text**`;
- `_italic text_`;
- headings beginning with one through six `#` characters;
- unordered list items beginning with `- ` or `* `; and
- ordered list items beginning with a number and `. `.

Formatting markers should open and close on the same source line. A `heading`
block is already rendered as the primary page heading; Markdown headings are
most useful inside a `body` block.

No other raw HTML is allowed. Links, images, code execution, embedded media,
iframes, scripts, CSS, event handlers, remote fonts, arbitrary font names,
pixel sizes, and arbitrary style values are not part of this contract. The UI
constructs React text elements and does not use raw-HTML injection.

## Shipped example

```yaml
schema_version: 2

display_name: Ishikawa
tagline: Knowledge assistant

ui:
  quick_questions:
    - What policy governs this situation?
    - Summarize the applicable operating procedure.
    - What reporting steps are required?

  footer_notice: Verify provided information using official documents.

  empty_chat:
    blocks:
      - type: heading
        font: serif
        size: display
        markdown: |
          **What would you like**
          **to understand?**

      - type: body
        font: sans
        size: medium
        markdown: |
          Ask questions across approved policy, regulation, conduct, and procedure sources.
```

## Multiline instructions example

```yaml
ui:
  quick_questions: []
  footer_notice: Verify provided information using official documents.
  empty_chat:
    blocks:
      - type: heading
        font: serif
        size: display
        markdown: |
          **Ask the policy library**
      - type: body
        font: sans
        size: medium
        markdown: |
          Describe the situation in your own words.<br>
          Include the relevant role, event, and date when known.

          **Useful details**
          - What happened
          - Who was involved
          - What decision is needed
```

The surrounding root keys `schema_version`, `display_name`, and `tagline` are
still required; this abbreviated example shows only the changed `ui` mapping.

## Invalid examples

These values stop startup:

```yaml
# Arbitrary HTML is rejected.
markdown: '<span style="font-size:72px">Unsafe</span>'

# Fonts and sizes must use the exact approved tokens.
font: Comic Sans MS
size: 72px

# Unknown keys are rejected instead of ignored.
color: purple
```

## Applying a change

1. Edit the installed `config/product.yaml` as ordinary UTF-8 YAML.
2. Start Ishikawa normally with `scripts/ishikawa-stack start`.
3. If validation blocks startup, correct the reported product reason code;
   do not bypass the validator.
4. Reload the browser after the stack reports ready.

Product copy is not a prompt, is not sent to Gemma or Nomic, and does not
change the corpus, retrieval lanes, citation validation, or answer contract.
