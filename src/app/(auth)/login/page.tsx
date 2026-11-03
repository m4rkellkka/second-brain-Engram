import type { Metadata } from "next";
import { EngramMark } from "@/components/app-shell/engram-mark";
import { LoginForm } from "@/features/auth/login-form";

export const metadata: Metadata = { title: "Sign in" };

export default function LoginPage() {
  return (
    <main className="flex min-h-dvh items-center justify-center px-4 py-12">
      <div className="w-full max-w-sm rounded-card border bg-surface p-6">
        <div className="flex items-center gap-2.5">
          <EngramMark className="size-6 text-primary" />
          <span className="text-lg font-semibold tracking-tight">Engram</span>
        </div>
        <h1 className="mt-6 mb-6 text-2xl font-semibold tracking-tight">
          Sign in
        </h1>
        <LoginForm />
      </div>
    </main>
  );
}
