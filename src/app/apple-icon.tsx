import { ImageResponse } from "next/og";

// iOS home-screen icon. Full-bleed square: iOS rounds the corners itself.
export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "#09090B",
      }}
    >
      <svg
        width="116"
        height="116"
        viewBox="0 0 24 24"
        fill="none"
        stroke="#8B9CFF"
        strokeWidth="1.8"
        strokeLinecap="round"
      >
        <circle cx="6" cy="6" r="2.5" />
        <circle cx="18" cy="8" r="2.5" />
        <circle cx="10" cy="18" r="2.5" />
        <path d="M8.2 7 15.6 7.8M7 8.3l2.2 7.4M16.6 10.1l-4.8 6.2" />
      </svg>
    </div>,
    size,
  );
}
