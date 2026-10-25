import assert from "node:assert/strict";
import test from "node:test";

import {
  loadServerRuntimeConfig,
  validateProductConfigurationBase64,
  validateRetrievalBaseUrl,
} from "../lib/runtime-config.mjs";

const productConfiguration = {
  empty_chat: {
    blocks: [
      {
        font: "serif",
        markdown: "**What would you like**\n**to understand?**",
        size: "display",
        type: "heading",
      },
    ],
  },
  footer_notice: "Verify provided information using official documents.",
  quick_questions: ["What policy applies?"],
  tagline: "Knowledge assistant",
};
const encodedProductConfiguration = Buffer.from(
  JSON.stringify(productConfiguration),
  "utf8",
).toString("base64url");

test("runtime configuration accepts the frozen loopback defaults", () => {
  assert.deepEqual(
    loadServerRuntimeConfig({
      ISHIKAWA_PRODUCT_DISPLAY_NAME: "Ishikawa",
      ISHIKAWA_PRODUCT_UI_CONFIG_BASE64: encodedProductConfiguration,
      ISHIKAWA_RETRIEVAL_BASE_URL: "http://127.0.0.1:1384",
    }),
    {
      productName: "Ishikawa",
      productConfiguration: {
        emptyChat: {
          blocks: [{
            font: "serif",
            markdown: "**What would you like**\n**to understand?**",
            size: "display",
            type: "heading",
          }],
        },
        footerNotice: "Verify provided information using official documents.",
        quickQuestions: ["What policy applies?"],
        tagline: "Knowledge assistant",
      },
      retrievalBaseUrl: "http://127.0.0.1:1384",
    },
  );
});

test("product configuration accepts only the bounded presentation contract", () => {
  const result = validateProductConfigurationBase64(encodedProductConfiguration);
  assert.equal(result.tagline, "Knowledge assistant");
  assert.equal(result.emptyChat.blocks[0].font, "serif");
  const unsafe = structuredClone(productConfiguration);
  unsafe.empty_chat.blocks[0].markdown = "<script>alert(1)</script>";
  assert.throws(
    () => validateProductConfigurationBase64(
      Buffer.from(JSON.stringify(unsafe), "utf8").toString("base64url"),
    ),
    /product_empty_chat_markup_invalid/u,
  );
});

test("retrieval configuration rejects credentials and non-loopback hosts", () => {
  assert.throws(
    () => validateRetrievalBaseUrl("http://10.0.0.10:1384"),
    /retrieval_base_url_invalid/u,
  );
  assert.throws(
    () => validateRetrievalBaseUrl("http://user:secret@127.0.0.1:1384"),
    /retrieval_base_url_invalid/u,
  );
});
