import { z } from "zod";

/** Project palette from the design tokens (`--project-1` … `--project-6`). */
export const PROJECT_COLORS = [
  "#B79CFF",
  "#F2A65A",
  "#3FD0B6",
  "#7FA8FF",
  "#F48FB1",
  "#C9E26B",
] as const;

export const MAX_PROJECT_NAME_LENGTH = 60;

export const projectNameSchema = z
  .string()
  .trim()
  .min(1, "Name the project.")
  .max(MAX_PROJECT_NAME_LENGTH, "Keep the name under 60 characters.");

// prettier-ignore
const CYRILLIC: Record<string, string> = {
  а: "a", б: "b", в: "v", г: "g", д: "d", е: "e", ё: "e", ж: "zh",
  з: "z", и: "i", й: "y", к: "k", л: "l", м: "m", н: "n", о: "o",
  п: "p", р: "r", с: "s", т: "t", у: "u", ф: "f", х: "kh", ц: "ts",
  ч: "ch", ш: "sh", щ: "shch", ъ: "", ы: "y", ь: "", э: "e", ю: "yu",
  я: "ya", і: "i", ї: "yi", є: "ye", ґ: "g",
};

const MAX_SLUG_LENGTH = 48;

/**
 * URL-safe slug that matches the `projects.slug` check
 * (`^[a-z0-9]+(-[a-z0-9]+)*$`). Cyrillic is transliterated, because most
 * project names here are Russian; anything else unusable becomes `project`.
 */
export function slugify(name: string): string {
  // Transliterate before decomposing: NFKD would split "й" into "и" + a mark.
  const slug = [...name.toLowerCase().normalize("NFC")]
    .map((char) => CYRILLIC[char] ?? char)
    .join("")
    .normalize("NFKD")
    .replace(/\p{M}/gu, "") // "é" → "e"
    .replace(/[^a-z0-9]+/g, "-")
    .slice(0, MAX_SLUG_LENGTH)
    .replace(/^-+|-+$/g, "");
  return slug || "project";
}

/** `base`, or `base-2`, `base-3`, … if the user already has that slug. */
export function uniqueSlug(base: string, taken: Iterable<string>): string {
  const used = new Set(taken);
  if (!used.has(base)) return base;
  for (let n = 2; ; n++) {
    const candidate = `${base}-${n}`;
    if (!used.has(candidate)) return candidate;
  }
}

/** First palette color no project uses yet, else the least used one. */
export function pickColor(usedColors: Iterable<string>): string {
  const counts = new Map<string, number>(
    PROJECT_COLORS.map((color) => [color, 0]),
  );
  for (const color of usedColors) {
    const key = color.toUpperCase();
    const count = counts.get(key);
    if (count !== undefined) counts.set(key, count + 1);
  }
  let best: string = PROJECT_COLORS[0];
  for (const color of PROJECT_COLORS) {
    if ((counts.get(color) ?? 0) < (counts.get(best) ?? 0)) best = color;
  }
  return best;
}
