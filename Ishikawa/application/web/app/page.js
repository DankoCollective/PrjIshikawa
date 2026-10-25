import ChatWorkspace from "../components/chat-workspace.js";
import { loadServerRuntimeConfig } from "../lib/runtime-config.mjs";

export const dynamic = "force-dynamic";

export default function HomePage() {
  const { productConfiguration, productName } = loadServerRuntimeConfig();
  return (
    <ChatWorkspace
      productConfiguration={productConfiguration}
      productName={productName}
    />
  );
}
