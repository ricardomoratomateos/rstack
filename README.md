# rstack

A small, personal pack of Claude Code skills, in the same spirit as [gstack](https://github.com/garrytan/gstack): markdown skill files with hard gates, not just suggestions.

## Skills

| Skill | Use it when | What it does |
|---|---|---|
| [rstack-investigate](rstack-investigate/SKILL.md) | You have a bug report and want the cause, not a guess | Root-cause debugging in phases, with a stop after each one. Iron Law: no fix without the bug reproduced, as a test in the repo, with real data. |
| [rstack-plan](rstack-plan/SKILL.md) | You describe a new feature, not a bug | Propose-and-wait planning: listen, confirm, look for reusable code, negotiate the plan one question at a time, then a hard approval gate. It never implements anything. |
| [rstack-review](rstack-review/SKILL.md) | You want a PR reviewed | Review against every document in `knowledge/` and every ADR of the current project, exhaustively, with an explicit N/N coverage count. |
| [rstack-qa-review](rstack-qa-review/SKILL.md) | You want a PR checked in the browser | Autonomous QA in four stages (login, prepare, execute, memory) that read the PR, seed real data through the real API, drive the flows with Playwright, capture evidence and deliver a `go` / `warn` / `no` verdict. See [how it works](rstack-qa-review/README.md). |

## Install

Requires [Claude Code](https://claude.com/claude-code). `rstack-review` and `rstack-qa-review` also need the [GitHub CLI](https://cli.github.com) (`gh`) to read PRs. `rstack-qa-review` installs the Playwright CLI itself on its first run.

```bash
git clone https://github.com/ricardomoratomateos/rstack.git ~/rstack   # or anywhere else, then adjust the paths below
for s in ~/rstack/rstack-*; do
  ln -s "$s" ~/.claude/skills/"$(basename "$s")"
done
```

Symlinks matter for `rstack-investigate` and `rstack-review`: they find `knowledge/` from the real location of their folder, one level up. `rstack-plan` and `rstack-qa-review` do not need it. If you copy the folders instead of linking them, point to the knowledge base explicitly:

```bash
export RSTACK_KNOWLEDGE=~/rstack/knowledge
```

If the skills cannot find `knowledge/`, they stop and ask you where it is.

### Optional: diagrams in `rstack-plan`

`rstack-plan` can draw workflow and sequence diagrams with [archify](https://github.com/tt-a1i/archify), a separate open-source skill (MIT):

```bash
npx skills add tt-a1i/archify -g
```

It is optional. If archify is not listed among your available skills, the plan says so and continues in text only.

## Example

An illustrative, abbreviated session (the names are made up):

```text
> /rstack-investigate Some checkout orders arrive without their discount (ticket #123)

Phase 1: Root cause investigation
  Symptom:     as reported in the ticket
  Reproduced:  tests/Checkout/DiscountTest.php fails (RED), built with the real payload from the ticket
  Hypothesis:  the discount is dropped when the cart is edited after payment starts
Checkpoint: proceed to Phase 2?
```

The skill stops there and waits. Each phase ends the same way: it reports what it found and asks before moving on.

## knowledge/

A personal engineering-principles knowledge base: one document per area (architecture, databases, testing, domain modelling). `rstack-review` and `rstack-investigate` read it in full, and you can also import single documents into any project's `CLAUDE.md`. See [knowledge/README.md](knowledge/README.md) for the index.

## Design principles

- Each skill is self-contained: no shared "philosophy" doc referenced from multiple skills. Some duplication across skills is preferred over a cross-reference that is easy to skip.
- Gates are phrased as hard stops ("do not do X until Y"), not soft advice ("you should probably do X").
- Any step that says "read everything" or "check all of X" is delegated to a fresh subagent with an explicit N/N completion count: a model already loaded with context tends to turn "review everything" into "skim what looks relevant."

## License

[MIT](LICENSE)
