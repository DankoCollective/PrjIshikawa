import "./globals.css";

import { loadServerRuntimeConfig } from "../lib/runtime-config.mjs";

export const dynamic = "force-dynamic";

export function generateMetadata() {
  const { productConfiguration, productName } = loadServerRuntimeConfig();
  return {
    description: productConfiguration.tagline,
    title: productName,
  };
}

export default function RootLayout({ children }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script src="/theme-init.js" />
      </head>
      <body>{children}</body>
    </html>
  );
}
