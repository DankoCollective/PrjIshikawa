import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const component = await readFile(new URL("../components/chat-workspace.js", import.meta.url), "utf8");
const presentationMarkdown = await readFile(new URL("../components/presentation-markdown.js", import.meta.url), "utf8");
const chatRoute = await readFile(new URL("../app/api/v1/chat/route.js", import.meta.url), "utf8");
const styles = await readFile(new URL("../app/globals.css", import.meta.url), "utf8");
const layout = await readFile(new URL("../app/layout.js", import.meta.url), "utf8");
const themeInit = await readFile(new URL("../public/theme-init.js", import.meta.url), "utf8");

test("workspace carries the applicable Anderson shell without code-assistant controls", () => {
  for (const required of [
    "app-header",
    "brand-block",
    "left-rail",
    "conversation-scroll",
    "composer-region",
    "right-rail",
    "Citations",
    "Model connections",
    "View full document",
    "Reconstructed active document",
    "Developer diagnostics",
    "Packed citations",
    "Searching documents",
    "Tag:",
    "Select a question or response to view its citations.",
  ]) {
    assert.match(component, new RegExp(required, "u"));
  }
  for (const excluded of ["Code assistance", "Upload code", "Model selector", "Artifact plan"]) {
    assert.doesNotMatch(component, new RegExp(excluded, "u"));
  }
  for (const removed of [
    "Content-free",
    "Gemma + Nomic ready",
    "Request context",
    "Selected turn",
    "Session overview",
    "Select a grounded question or response",
    "Your approved knowledge",
    "Grounded answer",
    "Retrieving grounded evidence",
    "Measured after the first grounded answer",
    "Cited results",
  ]) {
    assert.doesNotMatch(component, new RegExp(removed, "u"));
  }
});

test("product presentation is configured and renders no raw HTML", () => {
  assert.match(component, /productConfiguration\.quickQuestions/u);
  assert.match(component, /productConfiguration\.emptyChat\.blocks/u);
  assert.match(component, /productConfiguration\.footerNotice/u);
  assert.doesNotMatch(component, /welcome-actions|welcome-kicker/u);
  assert.match(presentationMarkdown, /InlineMarkdown/u);
  assert.doesNotMatch(presentationMarkdown, /dangerouslySetInnerHTML/u);
});

test("answers flow as cited segments and document bodies stay outside session storage", () => {
  assert.match(component, /message\.segments/u);
  assert.match(component, /segment-citations/u);
  assert.doesNotMatch(component, /className="claims"/u);
  assert.match(component, /const \[documentViewers, setDocumentViewers\] = useState/u);
  assert.doesNotMatch(component, /JSON\.stringify\(\{ activeId, conversations, documentViewers/u);
  assert.match(styles, /\.document-section/u);
  assert.match(styles, /\.document-viewer-body/u);
  assert.ok(component.indexOf('className="source-actions"') < component.indexOf("groups.map"));
});

test("chat proxy spans the bounded retrieval workflow and distinguishes timeout", () => {
  assert.match(chatRoute, /RETRIEVAL_REQUEST_TIMEOUT_MS = 600_000/u);
  assert.match(chatRoute, /WEB_RETRIEVAL_TIMEOUT/u);
  assert.match(chatRoute, /timed out before a response was returned/u);
  assert.doesNotMatch(chatRoute, /AbortSignal\.timeout\(30000\)/u);
});

test("presentation has semantic light and dark themes with deterministic rail collapse", () => {
  assert.match(styles, /--primary:\s*#7c3aed/u);
  assert.match(styles, /:root\[data-theme="dark"\]/u);
  assert.match(styles, /grid-template-columns:\s*264px minmax\(560px, 1fr\) 320px/u);
  assert.match(styles, /@media \(max-width: 1080px\)[\s\S]*?\.right-rail\s*\{\s*display:\s*none/u);
  assert.match(styles, /@media \(max-width: 820px\)[\s\S]*?\.left-rail,[\s\S]*?display:\s*none/u);
});

test("theme is applied before hydration and stores only its bounded preference", () => {
  assert.match(layout, /suppressHydrationWarning/u);
  assert.match(layout, /src="\/theme-init\.js"/u);
  assert.match(themeInit, /localStorage\.getItem\("ishikawa\.theme"\)/u);
  assert.doesNotMatch(themeInit, /sessionStorage|prompt|message|response|citation/iu);
});
