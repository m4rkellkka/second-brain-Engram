import type { NextConfig } from "next";
// Validates env vars at dev/build start, so a missing value fails fast.
import "./src/lib/env";
import "./src/server/env";

const nextConfig: NextConfig = {
  cacheComponents: true,
  partialPrefetching: true,
  // The dev indicator overlaps the mobile header and tab bar in every corner.
  devIndicators: false,
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
