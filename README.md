# rstack

A small, personal pack of Claude Code skills, in the same spirit as [gstack](https://github.com/garrytan/gstack): markdown skill files with hard gates, not just suggestions.

## Skills

- **[rstack-investigate](rstack-investigate/SKILL.md)** — systematic root-cause debugging with hard gates against guessing. Iron Law: no fix without a bug reproduced with real data.
- **[rstack-plan](rstack-plan/SKILL.md)** — propose-and-wait planning for new features. Listen, confirm understanding, survey for reusable code, negotiate the plan question by question with incremental diagrams, then a hard approval gate. Never implements anything itself.
- **[rstack-review](rstack-review/SKILL.md)** — PR review against `knowledge/` and every ADR of the current project, exhaustively (no topic sampling).

## knowledge/

A personal engineering-principles knowledge base (formerly the standalone `ricardo-knowledge` repo, folded in here via `git subtree`). Both skills read it directly from `~/Projects/rstack/knowledge`.

## Design principles

- Each skill is self-contained — no shared "philosophy" doc referenced from multiple skills. Some duplication across skills is preferred over a cross-reference that's easy to skip.
- Gates are phrased as hard stops ("do not do X until Y"), not soft advice ("you should probably do X").
- Any step that says "read everything" or "check all of X" is delegated to a fresh subagent with an explicit N/N completion count — a model already loaded with context tends to turn "review everything" into "skim what looks relevant."
