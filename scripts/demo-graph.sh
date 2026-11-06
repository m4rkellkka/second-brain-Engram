#!/bin/bash
# Builds a throwaway database with synthetic entries (2,000 by default) in
# a number of projects (8 by default), about 1.5 links per entry and a
# journal day every third day, all spread over one year, then opens the
# Brain graph on it. Your real data is never touched.
# Usage: make demo-graph [COUNT=2000] [PROJECTS=8]
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP=$ROOT/build/DerivedData/Build/Products/Debug/Engram.app
OUT=$ROOT/build/demo-graph
COUNT=${COUNT:-2000}
PROJECTS=${PROJECTS:-8}

NAMES=(Engram Учёба Tamam Здоровье Шахматы Машина Lumis Путешествия Музыка Спорт
  Книги Финансы Дом Работа Курсовая Английский Фотография Кулинария Стартап Игры
  Друзья Сад Велосипед Японский)
COLORS=('#B79CFF' '#F2A65A' '#3FD0B6' '#7FA8FF' '#F48FB1' '#C9E26B')
[ "$PROJECTS" -ge 1 ] && [ "$PROJECTS" -le ${#NAMES[@]} ] ||
  { echo "PROJECTS must be 1 to ${#NAMES[@]}"; exit 1; }

[ -d "$APP" ] || { echo "Build the app first: make build"; exit 1; }
rm -rf "$OUT" && mkdir -p "$OUT"
DB=$OUT/demo.sqlite
"$APP/Contents/MacOS/Engram" --mcp -EngramDatabasePath "$DB" </dev/null >/dev/null 2>&1

PROJECT_ROWS=""
for ((p = 0; p < PROJECTS; p++)); do
  [ -n "$PROJECT_ROWS" ] && PROJECT_ROWS+=","
  PROJECT_ROWS+="('p$p', '${NAMES[$p]}', 'demo-$p', '${COLORS[$((p % ${#COLORS[@]}))]}', 'ai', 'ai', '2026-01-01 00:00:00.000')"
done

sqlite3 "$DB" <<SQL
insert into projects (id, name, slug, color, summary_source, status_source, created_at) values
  $PROJECT_ROWS;
insert into captures values ('demo', 'claude', 'Synthetic demo data', 'demo', 'demo', 'sorted',
  'Europe/Istanbul', '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000');

-- Uneven project sizes; every 13th entry has no project.
with recursive n(i) as (select 0 union all select i + 1 from n where i + 1 < $COUNT)
insert into entries (id, capture_id, project_id, kind, content, keywords, needs_review, created_at, updated_at)
select 'e' || i, 'demo',
  case when i % 13 = 0 then null else 'p' || ((i * i + i / 7) % $PROJECTS) end,
  case i % 4 when 0 then 'note' when 1 then 'task' when 2 then 'idea' else 'link' end,
  'Demo entry ' || i, null, 0,
  strftime('%Y-%m-%d %H:%M:%f', '2026-01-01', '+' || (i * 525600 / $COUNT) || ' minutes'),
  strftime('%Y-%m-%d %H:%M:%f', '2026-01-01', '+' || (i * 525600 / $COUNT) || ' minutes')
from n;

-- A journal day every third day over the same stretch, for the timeline.
with recursive d(i) as (select 0 union all select i + 3 from d where i + 3 < 365)
insert into journal_days (day, time_zone, created_at, updated_at)
select date('2026-01-01', '+' || i || ' days'), 'Europe/Istanbul',
  strftime('%Y-%m-%d 18:00:00.000', '2026-01-01', '+' || i || ' days'),
  strftime('%Y-%m-%d 18:00:00.000', '2026-01-01', '+' || i || ' days')
from d;
insert into journal_paragraphs (id, day, author, text, created_at)
select 'j' || day, day, 'claude', 'Demo journal day ' || day, created_at from journal_days;

-- About 1.5 links per entry: neighbours in the same project, plus a few
-- links across projects.
insert or ignore into entry_links (source_id, target_id, weight)
select id, next1, 0.9 from (
  select id, lead(id, 1) over (partition by project_id order by rowid) as next1
  from entries where project_id is not null
) where next1 is not null;
insert or ignore into entry_links (source_id, target_id, weight)
select id, next5, 0.6 from (
  select id, rowid as r, lead(id, 5) over (partition by project_id order by rowid) as next5
  from entries where project_id is not null
) where next5 is not null and r % 2 = 0;
insert or ignore into entry_links (source_id, target_id, weight)
select a.id, b.id, 0.3 from entries a join entries b on b.rowid = ((a.rowid * 31 + 7) % $COUNT) + 1
where a.rowid % 17 = 0 and a.id != b.id;
SQL

echo "$(sqlite3 "$DB" 'select count(*) from entries') entries, $(sqlite3 "$DB" 'select count(*) from entry_links') links"
pkill -x Engram 2>/dev/null || true
open -n "$APP" --args -EngramDatabasePath "$DB" -EngramSection brain
