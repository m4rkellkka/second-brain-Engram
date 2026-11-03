import type { NextConfig } from "next";
// Validates env vars at dev/build start, so a missing value fails fast.
import "./src/lib/env";

const nextConfig: NextConfig = {
  cacheComponents: true,
  partialPrefetching: true,
  // Keep the dev indicator away from the mobile tab bar.
  devIndicators: { position: "top-right" },
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
  async redirects() {
    return [{ source: "/", destination: "/capture", permanent: false }];
  },
};

export default nextConfig;
