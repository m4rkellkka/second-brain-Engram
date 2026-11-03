import type { Metadata } from "next";
import { CaptureForm } from "@/features/capture/capture-form";

export const metadata: Metadata = { title: "Capture" };

export default function CapturePage() {
  return <CaptureForm />;
}
