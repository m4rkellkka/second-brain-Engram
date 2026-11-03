"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { signIn, type LoginState } from "./actions";

const initialState: LoginState = { status: "idle" };

export function LoginForm() {
  const [state, formAction, pending] = useActionState(signIn, initialState);
  const error = state.status === "error" ? state.message : null;
  const lastEmail = state.status === "error" ? state.email : "";
  const describedBy = error ? "login-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <div className="flex flex-col gap-2">
        <Label htmlFor="email">Email</Label>
        <Input
          id="email"
          name="email"
          type="email"
          autoComplete="username"
          inputMode="email"
          autoCapitalize="none"
          spellCheck={false}
          defaultValue={lastEmail}
          required
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          className="h-11 rounded-lg text-base"
        />
      </div>
      <div className="flex flex-col gap-2">
        <Label htmlFor="password">Password</Label>
        <Input
          id="password"
          name="password"
          type="password"
          autoComplete="current-password"
          required
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          className="h-11 rounded-lg text-base"
        />
      </div>
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
        {pending ? "Signing in…" : "Sign in"}
      </Button>
    </form>
  );
}
