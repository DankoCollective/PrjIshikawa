/**
 * Server-only web configuration.
 *
 * The container launcher derives these values from the validated product and
 * deployment YAML. These values remain on the server and are not compiled
 * into browser JavaScript.
 */

const LOOPBACK_HOSTS = new Set(["127.0.0.1", "localhost", "[::1]"]);
const PRODUCT_CONFIGURATION_BASE64 = /^[A-Za-z0-9_-]+={0,2}$/u;
const BLOCK_TYPES = new Set(["heading", "body"]);
const FONT_TOKENS = new Set(["sans", "serif", "mono"]);
const SIZE_TOKENS = new Set(["small", "medium", "large", "display"]);
const BREAK_TAG = /<br\s*\/?>/giu;

function requiredText(value, label, maximumLength) {
  if (
    typeof value !== "string" ||
    value.trim() !== value ||
    value.length < 1 ||
    value.length > maximumLength ||
    /[\u0000-\u001f\u007f]/u.test(value)
  ) {
    throw new Error(`${label}_invalid`);
  }
  return value;
}

function exactObject(value, fields, label) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label}_invalid`);
  }
  const actual = Object.keys(value).sort();
  const expected = [...fields].sort();
  if (actual.length !== expected.length || actual.some((item, index) => item !== expected[index])) {
    throw new Error(`${label}_invalid`);
  }
  return value;
}

function markdownText(value) {
  if (
    typeof value !== "string" ||
    value.trim() !== value ||
    value.length < 1 ||
    value.length > 4096 ||
    /[\u0000-\u0009\u000b-\u001f\u007f]/u.test(value)
  ) {
    throw new Error("product_empty_chat_markdown_invalid");
  }
  const withoutBreaks = value.replace(BREAK_TAG, "");
  if (withoutBreaks.includes("<") || withoutBreaks.includes(">")) {
    throw new Error("product_empty_chat_markup_invalid");
  }
  return value;
}

export function validateProductConfigurationBase64(value) {
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > 65536 ||
    !PRODUCT_CONFIGURATION_BASE64.test(value)
  ) {
    throw new Error("product_configuration_invalid");
  }
  let decoded;
  try {
    decoded = JSON.parse(Buffer.from(value, "base64url").toString("utf8"));
  } catch {
    throw new Error("product_configuration_invalid");
  }
  const root = exactObject(
    decoded,
    ["empty_chat", "footer_notice", "quick_questions", "tagline"],
    "product_configuration",
  );
  const emptyChat = exactObject(root.empty_chat, ["blocks"], "product_empty_chat");
  if (!Array.isArray(root.quick_questions) || root.quick_questions.length > 8) {
    throw new Error("product_quick_questions_invalid");
  }
  const quickQuestions = root.quick_questions.map((question) => (
    requiredText(question, "product_quick_question", 512)
  ));
  if (new Set(quickQuestions).size !== quickQuestions.length) {
    throw new Error("product_quick_questions_invalid");
  }
  if (!Array.isArray(emptyChat.blocks) || emptyChat.blocks.length < 1 || emptyChat.blocks.length > 8) {
    throw new Error("product_empty_chat_blocks_invalid");
  }
  const blocks = emptyChat.blocks.map((rawBlock) => {
    const block = exactObject(
      rawBlock,
      ["font", "markdown", "size", "type"],
      "product_empty_chat_block",
    );
    if (
      !BLOCK_TYPES.has(block.type) ||
      !FONT_TOKENS.has(block.font) ||
      !SIZE_TOKENS.has(block.size)
    ) {
      throw new Error("product_empty_chat_block_invalid");
    }
    return Object.freeze({
      font: block.font,
      markdown: markdownText(block.markdown),
      size: block.size,
      type: block.type,
    });
  });
  if (blocks.reduce((total, block) => total + block.markdown.length, 0) > 8192) {
    throw new Error("product_empty_chat_blocks_invalid");
  }
  return Object.freeze({
    emptyChat: Object.freeze({ blocks: Object.freeze(blocks) }),
    footerNotice: requiredText(root.footer_notice, "product_footer_notice", 512),
    quickQuestions: Object.freeze(quickQuestions),
    tagline: requiredText(root.tagline, "product_tagline", 256),
  });
}

export function validateRetrievalBaseUrl(value) {
  const text = requiredText(value, "retrieval_base_url", 2048);
  let parsed;
  try {
    parsed = new URL(text);
  } catch {
    throw new Error("retrieval_base_url_invalid");
  }
  if (
    parsed.protocol !== "http:" ||
    !LOOPBACK_HOSTS.has(parsed.hostname) ||
    !parsed.port ||
    parsed.username ||
    parsed.password ||
    (parsed.pathname !== "/" && parsed.pathname !== "") ||
    parsed.search ||
    parsed.hash
  ) {
    throw new Error("retrieval_base_url_invalid");
  }
  return parsed.origin;
}

export function loadServerRuntimeConfig(environment = process.env) {
  const productName = requiredText(
    environment.ISHIKAWA_PRODUCT_DISPLAY_NAME,
    "product_display_name",
    128,
  );
  const retrievalBaseUrl = validateRetrievalBaseUrl(
    environment.ISHIKAWA_RETRIEVAL_BASE_URL,
  );
  const productConfiguration = validateProductConfigurationBase64(
    environment.ISHIKAWA_PRODUCT_UI_CONFIG_BASE64,
  );
  return Object.freeze({ productConfiguration, productName, retrievalBaseUrl });
}
