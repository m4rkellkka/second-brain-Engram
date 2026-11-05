# Expected results

What a good save looks like for each conversation. `run.sh` prints the
actual entries; compare them by hand.

| # | Conversation | Expected entries |
| - | ------------ | ---------------- |
| 01 | Engram search | note "FTS5, no embeddings" → engram; task "search tests" → engram, due this Friday |
| 02 | Networks exam | tasks (review TCP/IP by Nov 10, old exams on Nov 11) and/or a note about the exam on Nov 12 → ucheba |
| 03 | Car | two tasks (car wash on Saturday, winter tyres by end of November), no project, suggested project like "Машина", needs review |
| 04 | Mixed day | note/decision "first month free" → tamam; task or note "sleep before midnight" → zdorove; idea "weekly task review" → engram |
| 05 | Link | link with the url → engram |
| 06 | English pricing | note "19 USD per month, annual plan two months free" → tamam; task "update landing page" → tamam, due Monday |
| 07 | Vague idea | idea "mobile app" → engram, possibly low confidence |
| 08 | Relative dates | task "send draft" due next Monday; task or note "defence in two weeks" → ucheba |
| 09 | Personal note | note → engram (or no project with review) |
| 10 | Sort inbox | typed thought 1 → tasks dentist + protein (zdorove); typed thought 2 → idea → tamam |

| 11 | Engram progress | contextUpdates for engram: decision "project pages are native SwiftUI", stack "GRDB", status like "beta" |
| 12 | Tamam pivot | Tamam summary stays the user's text (result says "kept the user's text"); status updated to "first customers" |
| 13 | Repeat | the FTS5 decision is not added twice (alreadyThere) |

Questions after the saves:

- "What did I decide about search?" → answers FTS5 without embeddings, citing that entry.
- "Open study tasks?" → lists the ucheba tasks with their due dates.
