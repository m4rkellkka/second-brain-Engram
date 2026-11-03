import type { MetadataRoute } from "next";

/** Web app manifest: installable PWA that opens straight on Capture. */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Engram",
    short_name: "Engram",
    description: "Your self-hosted second brain.",
    start_url: "/capture",
    scope: "/",
    display: "standalone",
    background_color: "#09090B",
    theme_color: "#09090B",
    icons: [
      { src: "/icon.svg", sizes: "any", type: "image/svg+xml" },
      { src: "/apple-icon", sizes: "180x180", type: "image/png" },
    ],
  };
}
