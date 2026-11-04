import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/server/db/database.types";
import { pickColor, slugify, uniqueSlug } from "./new-project";

type Result =
  { ok: true; id: string; slug: string } | { ok: false; message: string };

/**
 * Returns the user's active project with this name (case-insensitive) or
 * creates one with a unique slug and the next free palette color.
 * `name` must already be validated with projectNameSchema.
 */
export async function findOrCreateProject(
  supabase: SupabaseClient<Database>,
  name: string,
): Promise<Result> {
  const { data: auth } = await supabase.auth.getClaims();
  const userId = auth?.claims.sub;
  if (!userId) return { ok: false, message: "Sign in again." };

  const { data: projects, error: listError } = await supabase
    .from("projects")
    .select("id, name, slug, color, archived_at");
  if (listError)
    return { ok: false, message: "Couldn't create the project. Try again." };

  const active = projects.filter((project) => !project.archived_at);
  const existing = active.find(
    (project) => project.name.toLowerCase() === name.toLowerCase(),
  );
  if (existing) return { ok: true, id: existing.id, slug: existing.slug };

  const { data: created, error } = await supabase
    .from("projects")
    .insert({
      user_id: userId,
      name,
      slug: uniqueSlug(
        slugify(name),
        projects.map((project) => project.slug),
      ),
      color: pickColor(active.map((project) => project.color)),
    })
    .select("id, slug")
    .single();
  if (error)
    return { ok: false, message: "Couldn't create the project. Try again." };
  return { ok: true, id: created.id, slug: created.slug };
}
