#!/bin/bash
# Saves the sample conversations through the Engram connector with the real
# Claude (claude CLI, your subscription) into a throwaway database, then asks
# two questions and prints what landed where. Usage: make eval-connector
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
EVAL=$ROOT/evals/connector
BIN=$ROOT/build/DerivedData/Build/Products/Debug/Engram.app/Contents/MacOS/Engram
OUT=$ROOT/build/eval-connector
MODEL=${EVAL_MODEL:-sonnet}

[ -x "$BIN" ] || { echo "Build the app first: make build"; exit 1; }
command -v claude >/dev/null || { echo "The claude CLI is required."; exit 1; }

rm -rf "$OUT" && mkdir -p "$OUT"
DB=$OUT/eval.sqlite
"$BIN" --mcp -EngramDatabasePath "$DB" </dev/null >/dev/null 2>&1 # creates and migrates
sqlite3 "$DB" <"$EVAL/seed.sql"

cat >"$OUT/mcp.json" <<JSON
{"mcpServers": {"engram": {"command": "$BIN", "args": ["--mcp", "-EngramDatabasePath", "$DB"]}}}
JSON

ask() {
  (cd "$OUT" && claude -p "$(cat "$1")" --model "$MODEL" --restricted --tools "" \
    --strict-mcp-config --mcp-config "$OUT/mcp.json" --allowedTools "mcp__engram__*" \
    --no-session-persistence --output-format text </dev/null) >"$OUT/$(basename "$1" .md).reply.txt" 2>&1 ||
    echo "  failed: $(basename "$1")"
}

for file in "$EVAL"/conversations/*.md "$EVAL"/questions/*.md; do
  echo "→ $(basename "$file")"
  ask "$file"
done

sqlite3 -header -column "$DB" "
  select coalesce(c.conversation_ref, '(typed)') as conversation, e.kind,
    coalesce(p.slug, '-') as project, e.needs_review as review,
    coalesce(datetime(e.due_at, 'localtime'), '') as due_local, coalesce(e.suggested_project, '') as suggested,
    e.confidence as conf, e.content
  from entries e
  join captures c on c.id = e.capture_id
  left join projects p on p.id = e.project_id
  order by c.created_at, e.rowid" | tee "$OUT/results.txt"

echo
echo "== Project context"
sqlite3 -header -column "$DB" "
  select p.slug, p.status, p.status_source as status_by, p.summary_source as summary_by,
    substr(p.summary, 1, 60) as summary
  from projects p order by p.slug"
echo
sqlite3 -header -column "$DB" "
  select p.slug, i.section, i.source, json_array_length(i.entry_ids) as notes, i.text
  from project_context_items i join projects p on p.id = i.project_id
  where i.dismissed_at is null order by p.slug, i.section, i.created_at" | tee "$OUT/context.txt"

echo
echo "== Journal"
sqlite3 -header -column "$DB" "
  select day, author, datetime(created_at, 'localtime') as written_local, text
  from journal_paragraphs order by day, created_at" | tee "$OUT/journal.txt"

echo
for file in "$OUT"/0*-search-decision.reply.txt "$OUT"/0*-study-tasks.reply.txt \
  "$OUT"/0*-journal-week.reply.txt; do
  echo "== $(basename "$file")"
  cat "$file"
  echo
done
