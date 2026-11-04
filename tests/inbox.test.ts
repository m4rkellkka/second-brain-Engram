/** Inbox logic: project naming, the kind filter, action inputs, entry age. */
import { describe, expect, it } from "vitest";
import { formatAge } from "@/features/inbox/format-age";
import {
  assignNewProjectSchema,
  assignProjectSchema,
  parseKindFilter,
} from "@/features/inbox/schema";
import {
  PROJECT_COLORS,
  pickColor,
  slugify,
  uniqueSlug,
} from "@/features/projects/new-project";

const ENTRY_ID = "8f0c2a43-5a8e-4d1b-9c6e-2f4a7b1d3e5f";

describe("slugify", () => {
  it.each([
    ["Engram", "engram"],
    ["Chess Coach", "chess-coach"],
    ["  Tally / v2!  ", "tally-v2"],
    ["Жизнь", "zhizn"],
    ["Мойка машины", "moyka-mashiny"],
    ["Ёлка", "elka"],
    ["Café Ölbaum", "cafe-olbaum"],
    ["Учёба 2026", "ucheba-2026"],
  ])("%j → %j", (name, slug) => {
    expect(slugify(name)).toBe(slug);
  });

  it("falls back to `project` when nothing usable is left", () => {
    expect(slugify("🚀✨")).toBe("project");
    expect(slugify("---")).toBe("project");
  });

  it("always matches the database slug check", () => {
    const check = /^[a-z0-9]+(-[a-z0-9]+)*$/;
    for (const name of ["a  b", "-x-", "Щука и ёж", "x".repeat(80) + " y"]) {
      expect(slugify(name)).toMatch(check);
    }
  });

  it("caps the length without a trailing dash", () => {
    const slug = slugify(`${"a".repeat(47)} b`);
    expect(slug.length).toBeLessThanOrEqual(48);
    expect(slug.endsWith("-")).toBe(false);
  });
});

describe("uniqueSlug", () => {
  it("keeps a free slug", () => {
    expect(uniqueSlug("life", ["engram"])).toBe("life");
  });

  it("adds the first free number", () => {
    expect(uniqueSlug("life", ["life", "life-2"])).toBe("life-3");
  });
});

describe("pickColor", () => {
  it("starts with the first palette color", () => {
    expect(pickColor([])).toBe(PROJECT_COLORS[0]);
  });

  it("skips colors already in use, ignoring case", () => {
    expect(pickColor(["#b79cff", "#3FD0B6"])).toBe("#F2A65A");
  });

  it("reuses the least used color once all are taken", () => {
    expect(pickColor([...PROJECT_COLORS, ...PROJECT_COLORS.slice(0, 3)])).toBe(
      PROJECT_COLORS[3],
    );
  });
});

describe("parseKindFilter", () => {
  it.each(["idea", "task", "note", "link"])("accepts %s", (kind) => {
    expect(parseKindFilter(kind)).toBe(kind);
  });

  it.each([undefined, "", "all", "TASK", ["task"]])(
    "treats %j as all",
    (value) => {
      expect(parseKindFilter(value)).toBeNull();
    },
  );
});

describe("action inputs", () => {
  it("accepts a project id or null", () => {
    expect(
      assignProjectSchema.safeParse({ entryId: ENTRY_ID, projectId: null })
        .success,
    ).toBe(true);
    expect(
      assignProjectSchema.safeParse({ entryId: ENTRY_ID, projectId: ENTRY_ID })
        .success,
    ).toBe(true);
  });

  it("rejects ids that are not uuids", () => {
    expect(
      assignProjectSchema.safeParse({ entryId: "1", projectId: null }).success,
    ).toBe(false);
  });

  it("trims a new project name and rejects blank or long ones", () => {
    expect(
      assignNewProjectSchema.parse({ entryId: ENTRY_ID, name: "  Life " }).name,
    ).toBe("Life");
    for (const name of ["   ", "x".repeat(61)]) {
      expect(
        assignNewProjectSchema.safeParse({ entryId: ENTRY_ID, name }).success,
      ).toBe(false);
    }
  });
});

describe("formatAge", () => {
  const now = new Date("2026-11-04T12:00:00Z");
  const ago = (ms: number) => new Date(now.getTime() - ms);

  it.each([
    [30_000, "now"],
    [5 * 60_000, "5m"],
    [2 * 3_600_000, "2h"],
    [26 * 3_600_000, "1d"],
    [6 * 86_400_000, "6d"],
  ])("%d ms ago → %s", (ms, label) => {
    expect(formatAge(ago(ms), now)).toBe(label);
  });

  it("shows a date after a week", () => {
    expect(formatAge(new Date("2026-10-12T12:00:00Z"), now)).toBe("Oct 12");
    expect(formatAge(new Date("2025-10-12T12:00:00Z"), now)).toBe(
      "Oct 12, 2025",
    );
  });
});
