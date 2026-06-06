---
name: github-operations
description: Use for GitHub work in Polish Open Source Rank, including listing or inspecting pull requests from Dependabot or other authors, reviewing dependency updates, checking merge readiness, merging pull requests, reading GitHub Actions status and failed logs, rerunning transient failures, fixing CI failures, or dispatching the documented deploy or rollback workflow. Read docs/github-operations.md first and use bin/gh for every GitHub CLI command.
---

# GitHub Operations

## Required context

Read [docs/github-operations.md](../../docs/github-operations.md) before issuing
GitHub commands. For deploy or rollback work, also read
[docs/deployment.md](../../docs/deployment.md) and
[docs/operations-runbook.md](../../docs/operations-runbook.md).

Use `bin/gh`, not bare `gh`. The repository entrypoint resolves the Homebrew
binary when the shell `PATH` does not include it.

## Workflow

1. Verify identity and permission:
   - `bin/gh auth status`
   - `bin/gh repo view --json nameWithOwner,viewerPermission`
2. Inspect before writing:
   - list all open pull requests without filtering out human authors;
   - read PR metadata, diff, reviews, and checks;
   - inspect failed Actions logs before deciding on a fix or rerun.
3. Apply the documented policy:
   - dependency PRs require manifest, lockfile, and release-note review;
   - merge only on an explicit user request and only when checks and reviews
     satisfy the repository rules;
   - use squash merge;
   - rerun only demonstrably transient CI failures.
4. For code fixes:
   - reproduce locally;
   - make the narrowest coherent change;
   - run relevant tests and `bin/quality`;
   - commit and push without bypassing hooks;
   - verify the new GitHub checks.
5. For deploy or rollback:
   - follow the production docs;
   - verify the resulting workflow and smoke checks.

## Guardrails

- Never expose or persist GitHub tokens in repository files or output.
- Do not use admin merge, bypass protection, dismiss reviews, or merge with
  unresolved required checks unless the user explicitly accepts the stated
  risk.
- Do not assume pull request checks prove the post-merge deploy succeeded.
- Do not claim branch protection is absent solely because its API returned
  `404`.
- Request persistent sandbox approval for the narrow `bin/gh` prefix when
  available.

## Output

Report the repository and PR or run identifiers inspected, the evidence used
for the decision, every GitHub write performed, and any remaining failed,
pending, external, or unverified check.
