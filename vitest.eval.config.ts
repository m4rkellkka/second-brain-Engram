import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

// `pnpm eval:sort`: real model calls, so it costs money and is never part
// of `pnpm test` or CI.
export default defineConfig({
  resolve: {
    alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
  },
  test: {
    environment: "node",
    include: ["evals/**/*.eval.ts"],
    testTimeout: 600_000,
  },
});
