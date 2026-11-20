# Skills

Agent skills for auditing and maintaining codebases. Each skill is a folder
with a `SKILL.md`, in the [Agent Skills](https://agentskills.io) format, so it
works in Claude Code, the Claude apps and other agents that read that format.

| Skill | What it does |
|---|---|
| [`slop-hunt`](skills/slop-hunt/SKILL.md) | Audits a repository, a path or a branch's diff for slop and reports findings ranked by harm and certainty. |

## Install

**Claude Code, as a plugin:**

```
/plugin marketplace add melihucar/skills
/plugin install slop-hunt@melihucar-skills
```

**Claude Code, by hand:** copy the skill folder into your personal or project
skills directory.

```bash
git clone https://github.com/melihucar/skills.git
cp -R skills/skills/slop-hunt ~/.claude/skills/
```

**Other agents:** copy `skills/slop-hunt` wherever your agent loads skills
from. The skill works best when the agent can start subagents; without them it
runs every pass itself, which takes longer.

## slop-hunt

Slop is code and documentation that costs more to keep than it is worth: it
looks like work, passes a glance, and leaves the repo harder to trust. Copied
helpers, swallowed errors, silenced type checks, invented APIs, dead code,
narrating comments, tests that cannot fail, docs that say something the code
does not do.

`slop-hunt` finds it, proves it and ranks it. It judges every finding against
the repository's own conventions rather than a fixed list of bad tokens, so it
works in any language or framework, and it never claims that code "was written
by AI". Code a person wrote sloppily counts the same.

### Usage

Ask for it in plain words ("hunt for slop in this repo", "deslop the API
folder") or call it directly. Installed as a plugin, the command is
`/slop-hunt:slop-hunt`.

```
/slop-hunt                     # whole repository, standard depth
/slop-hunt src/billing         # one path
/slop-hunt --diff              # only what this branch changes against main
/slop-hunt --fast              # cheap first pass
/slop-hunt --deep              # exhaustive backlog; costs several times more
/slop-hunt --only 3,8          # only some categories, by number or name
/slop-hunt --fix               # apply the safe fixes after reporting
```

### How it works

1. **Learn the repo:** languages, tooling, the repo's own rules, and the house
   style of its oldest code. Every later judgement is made against that.
2. **Sweep:** run the repo's own linters and checkers, build a duplication
   index with [`scripts/dup-index.sh`](skills/slop-hunt/scripts/dup-index.sh)
   (POSIX sh, grep and awk; read-only), and search for the signals in the
   [catalogue](skills/slop-hunt/references/catalog.md). This produces leads.
3. **Read:** scouts on three model tiers turn leads into findings. Fast models
   take the high-volume categories, strong models the ones that need judgement,
   and one long-context scout holds the whole map for duplication and
   docs-versus-code. Each finding is checked against the usual false-positive
   causes and graded by harm (misleading, costly, noisy) and certainty
   (confirmed, probable, suspected).
4. **Report:** a verdict, hot spots, findings worst first, counts by category,
   what came back clean, and rules that would stop the worst patterns
   recurring.

The skill is read-only by default. It writes nothing into the repository,
creates GitHub issues only after showing you the full list and getting a yes,
and with `--fix` applies only changes that cannot alter behaviour. Merging
duplicates or changing error handling is listed as planned work, not done
quietly.

### Requirements

- An agent that can read files and run shell commands.
- `git`, a POSIX shell, `grep` and `awk` for the duplication index.
- Optional: a subagent tool (the Agent tool in Claude Code) for the parallel
  scouts, and the `gh` CLI for turning findings into issues.

### Limits

- The duplication index finds function definitions by keyword (`function`,
  `def`, `fn`, `func`, `fun`, `sub`), by access modifier (`public`, `private`,
  …) and by JavaScript bindings. Methods in C-like languages declared without a
  modifier are not indexed; the scouts still read them.
- A `--deep` run on a large repository can start dozens of subagents. The skill
  states the count and asks before going past twelve.

## License

[MIT](LICENSE)
