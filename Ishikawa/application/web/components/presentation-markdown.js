"use client";

import { Fragment } from "react";

/**
 * Render the deliberately small product-copy Markdown subset.
 *
 * Configuration is validated server-side before these blocks reach React.
 * This renderer creates React text nodes only: it never interprets raw HTML,
 * URLs, images, CSS, or arbitrary element attributes.
 */

const INLINE_MARKERS = /(<br\s*\/?>|\*\*[^*\n]+\*\*|_[^_\n]+_)/giu;
const ORDERED_ITEM = /^\d+\.\s+(.+)$/u;
const UNORDERED_ITEM = /^[-*]\s+(.+)$/u;
const HEADING = /^(#{1,6})\s+(.+)$/u;

function InlineMarkdown({ text }) {
  const pieces = text.split(INLINE_MARKERS);
  return pieces.map((piece, index) => {
    if (/^<br\s*\/?>$/iu.test(piece)) {
      return <br key={`break-${index}`} />;
    }
    if (piece.startsWith("**") && piece.endsWith("**")) {
      return <strong key={`bold-${index}`}>{piece.slice(2, -2)}</strong>;
    }
    if (piece.startsWith("_") && piece.endsWith("_")) {
      return <em key={`italic-${index}`}>{piece.slice(1, -1)}</em>;
    }
    return <Fragment key={`text-${index}`}>{piece}</Fragment>;
  });
}

function lineWithBreaks(lines, keyPrefix) {
  return lines.map((line, index) => (
    <Fragment key={`${keyPrefix}-${index}`}>
      {index > 0 ? <br /> : null}
      <InlineMarkdown text={line} />
    </Fragment>
  ));
}

function BodyMarkdown({ markdown }) {
  const lines = markdown.split("\n");
  const nodes = [];
  let index = 0;
  while (index < lines.length) {
    if (!lines[index].trim()) {
      index += 1;
      continue;
    }
    const heading = HEADING.exec(lines[index]);
    if (heading) {
      const Heading = `h${Math.min(6, heading[1].length + 1)}`;
      nodes.push(<Heading key={`heading-${index}`}><InlineMarkdown text={heading[2]} /></Heading>);
      index += 1;
      continue;
    }
    const unordered = UNORDERED_ITEM.exec(lines[index]);
    const ordered = ORDERED_ITEM.exec(lines[index]);
    if (unordered || ordered) {
      const List = unordered ? "ul" : "ol";
      const matcher = unordered ? UNORDERED_ITEM : ORDERED_ITEM;
      const items = [];
      while (index < lines.length) {
        const item = matcher.exec(lines[index]);
        if (!item) break;
        items.push(<li key={`item-${index}`}><InlineMarkdown text={item[1]} /></li>);
        index += 1;
      }
      nodes.push(<List key={`list-${index}`}>{items}</List>);
      continue;
    }
    const paragraph = [];
    while (
      index < lines.length &&
      lines[index].trim() &&
      !HEADING.test(lines[index]) &&
      !UNORDERED_ITEM.test(lines[index]) &&
      !ORDERED_ITEM.test(lines[index])
    ) {
      paragraph.push(lines[index]);
      index += 1;
    }
    nodes.push(<p key={`paragraph-${index}`}>{lineWithBreaks(paragraph, `line-${index}`)}</p>);
  }
  return nodes;
}

export default function PresentationMarkdown({ block }) {
  const className = `presentation-block block-${block.type} font-${block.font} size-${block.size}`;
  if (block.type === "heading") {
    return <h1 className={className}>{lineWithBreaks(block.markdown.split("\n"), "heading-line")}</h1>;
  }
  return <div className={className}><BodyMarkdown markdown={block.markdown} /></div>;
}
