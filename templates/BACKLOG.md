# Backlog

Every proposal this project deferred — from a plan's rulings, an accepted residual or a retrospective — with an id.
Ids are `BL-NNN` (three-digit zero-padded, globally unique, never reused; `art-naming-tagging`). Each entry carries a
**Source:**, a **Listed:** date, a **Proposal:**, optional **Absorbed:** (what already delivers it, in whole or in part) and
**Planned:** lines, and a **Status:** (open or decided).
Every retrospective records one decision line per open id in its `## Decisions on Prior Proposals`
(`/retrospective`): `- BL-NNN: accepted (landed: <PR/commit>) | accepted (target: <PR/owner>) | rejected (<why>) | deferred (<trigger>)`;
in the same PR it marks each decided entry **Status:** decided with a **Decision:** line naming that retrospective
(`<decision> — docs/retrospectives/<file>.md`), and lists each proposal it defers as a new id. Only a retrospective
writes decisions here.
