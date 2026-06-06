# GitHub operations

This repository uses GitHub CLI for pull request writes and GitHub Actions
inspection. Use the repository entrypoint:

```sh
bin/gh
```

Do not depend on `gh` being present in the shell `PATH`. Codex shells may omit
Homebrew paths even though GitHub CLI is installed at `/opt/homebrew/bin/gh`.
`bin/gh` resolves the installed binary and supports an explicit `GH_BIN`
override.

## Authentication and authorization

Authentication is stored by GitHub CLI in the operating system credential
store and survives new Codex sessions. Verify it before a GitHub operation:

```sh
bin/gh auth status
bin/gh repo view --json nameWithOwner,viewerPermission
```

The expected repository is `ciembor/polish-open-source`, and
`viewerPermission` must be `WRITE`, `MAINTAIN`, or `ADMIN` for merge and branch
write operations.

If authentication is missing or its scopes are insufficient, authenticate the
operator account once:

```sh
bin/gh auth login --hostname github.com --git-protocol ssh --web
bin/gh auth refresh --hostname github.com --scopes repo,workflow,read:org
```

Never copy or expose the GitHub CLI credential in repository files,
`.env.local`, skill files, command arguments, or chat output. GitHub CLI owns
its credential storage. The application's separately managed `GITHUB_TOKEN` in
`.env.local` is runtime configuration and must not be reused as the CLI
credential.

GitHub network commands may require sandbox approval. Request persistent
approval for the narrow `bin/gh` command prefix when the execution environment
supports persisted command rules.

## Pull request triage

List all open pull requests, including Dependabot and human-authored changes:

```sh
bin/gh pr list --state open --limit 100 \
  --json number,title,author,isDraft,updatedAt,url
```

Dependabot pull requests have `author.login` equal to `dependabot[bot]`. Do not
filter the initial list by author because other contributors and automation
must remain visible.

Inspect an individual pull request before changing it:

```sh
bin/gh pr view PR_NUMBER \
  --json number,title,author,baseRefName,headRefName,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,url
bin/gh pr diff PR_NUMBER
bin/gh pr checks PR_NUMBER
```

For dependency updates, inspect the manifest and lockfile changes, the upstream
release notes linked by Dependabot, and whether the update is major, minor, or
patch. Treat major updates and security-relevant behavior changes as code
changes requiring explicit compatibility review. Run the relevant local checks
when the diff can affect runtime behavior.

## Merge policy

Merge only when the user requested that write action and all of these are true:

- the pull request targets `master` and is not a draft;
- the diff is understood and contains no unrelated or suspicious changes;
- required reviews are satisfied;
- required checks have completed successfully;
- GitHub reports the pull request as mergeable and not blocked;
- any update-specific local verification has passed.

Use squash merge for this repository:

```sh
bin/gh pr merge PR_NUMBER --squash --delete-branch
```

If branch protection requires queued or delayed merging, use:

```sh
bin/gh pr merge PR_NUMBER --squash --delete-branch --auto
```

Do not bypass branch protection, use admin merge, dismiss reviews, or merge with
failing or pending required checks unless the user explicitly requests the
exception after the risk is stated. After merging, verify the resulting
`master` workflow rather than assuming the pull request checks cover deploy.

## GitHub Actions inspection

Inspect pull request checks:

```sh
bin/gh pr checks PR_NUMBER
```

Inspect recent runs on any branch:

```sh
bin/gh run list --workflow deploy.yml --limit 20
bin/gh run view RUN_ID
bin/gh run view RUN_ID --log-failed
```

The workflow is named `CI and deploy`. Its required pre-deploy jobs are
`Quality`, `Dependency security`, `CodeQL`, and `Container smoke`; `Deploy`
starts only after all four succeed.

When CI fails:

1. Read the failed job and step logs before editing.
2. Decide whether the failure is caused by the pull request, infrastructure, or
   an unrelated flaky dependency.
3. For a code failure, reproduce it with the narrowest local command, implement
   the fix, then run the relevant tests and `bin/quality`.
4. Commit and push the fix without skipping pre-commit hooks.
5. Recheck the pull request checks and report any remaining failure.
6. Rerun a failed job only when the failure is demonstrably transient:

```sh
bin/gh run rerun RUN_ID --failed
```

Do not rerun a deterministic code failure as a substitute for fixing it.

## Manual workflow actions

Normal deploys run after pushes to `master`. The documented one-step production
rollback is the only routine manual workflow action:

```sh
bin/gh workflow run deploy.yml --ref master -f action=rollback
```

Follow [Deployment](deployment.md) and
[Operations Runbook](operations-runbook.md) before dispatching or evaluating a
deploy or rollback.

## Stable machine-readable output

Prefer `--json` plus `--jq` for decisions and summaries. Avoid scraping
human-formatted tables. Useful repository identity checks are:

```sh
bin/gh repo view --json nameWithOwner,defaultBranchRef,viewerPermission
bin/gh api repos/ciembor/polish-open-source/branches/master/protection
```

Branch protection can return `404` when it is not configured or when the
authenticated account cannot read the setting. Distinguish those cases before
making claims about merge requirements.
