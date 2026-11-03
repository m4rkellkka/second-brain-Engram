"use client";

import { useActionState } from "react";
import { useSearchParams } from "next/navigation";
import { MailCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { sendMagicLink, type LoginState } from "./actions";

const initialState: LoginState = { status: "idle" };

export function LoginForm() {
  const [state, formAction, pending] = useActionState(
    sendMagicLink,
    initialState,
  );
  const linkFailed = useSearchParams().get("error") === "link";

  if (state.status === "sent") {
    return (
      <div role="status" className="flex flex-col items-center text-center">
        <MailCheck className="size-8 text-primary" aria-hidden="true" />
        <p className="mt-4 font-medium">Check your email</p>
        <p className="mt-1 text-sm text-muted-foreground">
          We sent a sign-in link to {state.email}. Open it on any device.
        </p>
      </div>
    );
  }

  const error =
    state.status === "error"
      ? state.message
      : linkFailed
        ? "That link is invalid or expired. Request a new one."
        : null;

  return (
    <form action={formAction} className="flex flex-col gap-3">
      <Label htmlFor="email">Email</Label>
      <Input
        id="email"
        name="email"
        type="email"
        autoComplete="email"
        inputMode="email"
        required
        placeholder="you@example.com"
        aria-invalid={error ? true : undefined}
        aria-describedby={error ? "login-error" : undefined}
        className="h-11 rounded-lg text-base"
      />
      {error && (
        <p id="login-error" role="alert" className="text-sm text-destructive">
          {error}
        </p>
      )}
      <Button
        type="submit"
        disabled={pending}
        className="mt-1 h-11 rounded-lg text-sm font-semibold"
      >
        {pending ? "Sending…" : "Send magic link"}
      </Button>
    </form>
  );
}
