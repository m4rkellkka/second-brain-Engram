-- Projects and typed thoughts the eval starts from (fixed ids, local test data only).
insert into projects (id, name, slug, color, summary_source, status_source, created_at) values
  ('p-engram', 'Engram', 'engram', '#B79CFF', 'ai', 'ai', '2026-11-01 09:00:00.000'),
  ('p-ucheba', 'Учёба', 'ucheba', '#F2A65A', 'ai', 'ai', '2026-11-01 09:00:00.000'),
  ('p-tamam', 'Tamam', 'tamam', '#3FD0B6', 'ai', 'ai', '2026-11-01 09:00:00.000'),
  ('p-health', 'Здоровье', 'zdorove', '#7FA8FF', 'ai', 'ai', '2026-11-01 09:00:00.000');
update projects set summary = 'Open-source second brain as a native Mac app (Swift, SQLite, Claude connector).' where id = 'p-engram';
update projects set summary = 'University courses this semester: computer networks, web design, automata theory.' where id = 'p-ucheba';
-- Written by the user: Claude must keep it ("user edits win").
update projects set summary = 'Моё описание: приложение для заказов в ресторанах.', summary_source = 'user' where id = 'p-tamam';
update projects set summary = 'Sleep, sport and doctor visits.' where id = 'p-health';

insert into captures values
  ('c-typed-1', 'typed', 'записаться к стоматологу на следующей неделе и купить протеин', null, 'h1', 'unsorted', 'Europe/Istanbul', '2026-11-04 08:00:00.000', null),
  ('c-typed-2', 'typed', 'idea: Tamam could send a weekly sales digest to owners', null, 'h2', 'unsorted', 'Europe/Istanbul', '2026-11-04 09:00:00.000', null);
insert into entries (id, capture_id, kind, content, needs_review, created_at, updated_at) values
  ('e-typed-1', 'c-typed-1', 'note', 'записаться к стоматологу на следующей неделе и купить протеин', 0, '2026-11-04 08:00:00.000', '2026-11-04 08:00:00.000'),
  ('e-typed-2', 'c-typed-2', 'note', 'idea: Tamam could send a weekly sales digest to owners', 0, '2026-11-04 09:00:00.000', '2026-11-04 09:00:00.000');

-- Journal days the user wrote earlier this week, relative to the day the
-- eval runs, so "how did I feel last week?" has something to answer from.
insert into journal_days (day, time_zone, created_at, updated_at) values
  (date('now', 'localtime', '-6 days'), 'Europe/Istanbul', datetime('now', '-6 days'), datetime('now', '-6 days')),
  (date('now', 'localtime', '-4 days'), 'Europe/Istanbul', datetime('now', '-4 days'), datetime('now', '-4 days')),
  (date('now', 'localtime', '-2 days'), 'Europe/Istanbul', datetime('now', '-2 days'), datetime('now', '-2 days'));
insert into journal_paragraphs (id, day, author, text, created_at) values
  ('j-1', date('now', 'localtime', '-6 days'), 'user', 'Тревожно из-за экзамена по сетям, почти ничего не успел повторить. Плохо спал.', datetime('now', '-6 days')),
  ('j-2', date('now', 'localtime', '-4 days'), 'user', 'Отличный день: Engram наконец заработал на Swift, чувствую прилив сил.', datetime('now', '-4 days')),
  ('j-3', date('now', 'localtime', '-2 days'), 'user', 'Устал, весь день на парах. Вечером погулял, стало легче.', datetime('now', '-2 days'));
