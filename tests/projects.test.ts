/** Project page inputs and the rules behind the context editors. */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  addContextItemSchema,
  setSummarySchema,
  updateProjectSchema,
} from "@/features/projects/schema";
import { createUser, deleteUsers, type Client } from "./support/local-supabase";

const ID = "8f0c2a43-5a8e-4d1b-9c6e-2f4a7b1d3e5f";

describe("project schemas", () => {
  it("accepts only palette colors", () => {
    expect(
      updateProjectSchema.safeParse({ projectId: ID, color: "#B79CFF" })
        .success,
    ).toBe(true);
    expect(
      updateProjectSchema.safeParse({ projectId: ID, color: "#000000" })
        .success,
    ).toBe(false);
  });

  it("treats a null summary as 'let the AI update it'", () => {
    expect(
      setSummarySchema.parse({ projectId: ID, summary: null }).summary,
    ).toBeNull();
    expect(
      setSummarySchema.parse({ projectId: ID, summary: "  mine  " }).summary,
    ).toBe("mine");
  });

  it("rejects blank items and unknown sections", () => {
    expect(
      addContextItemSchema.safeParse({
        projectId: ID,
        section: "idea",
        text: "  ",
      }).success,
    ).toBe(false);
    expect(
      addContextItemSchema.safeParse({
        projectId: ID,
        section: "task",
        text: "x",
      }).success,
    ).toBe(false);
  });
});

describe("context items", () => {
  let user: { id: string; client: Client };
  let other: { id: string; client: Client };
  let projectId = "";

  beforeAll(async () => {
    [user, other] = await Promise.all([createUser(), createUser()]);
    const { data } = await user.client
      .from("projects")
      .insert({ user_id: user.id, name: "P", slug: "p", color: "#B79CFF" })
      .select("id")
      .single();
    projectId = data!.id;
  });
  afterAll(() => deleteUsers([user?.id, other?.id]));

  it("rejects the same text twice in a section with a unique violation", async () => {
    const row = {
      user_id: user.id,
      project_id: projectId,
      section: "stack",
      source: "user",
    };
    expect(
      (
        await user.client
          .from("project_context_items")
          .insert({ ...row, text: "Supabase" })
      ).error,
    ).toBeNull();
    const dup = await user.client
      .from("project_context_items")
      .insert({ ...row, text: " supabase" });
    expect(dup.error?.code).toBe("23505");
  });

  it("cannot be edited by another user", async () => {
    const { data } = await other.client
      .from("project_context_items")
      .update({ text: "hijack" })
      .eq("project_id", projectId)
      .select("id");
    expect(data).toEqual([]);
  });
});
