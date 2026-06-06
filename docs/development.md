# Development

## Local Setup

```sh
bin/bundle install
cp .env.local.example .env.local
```

Add your tokens and local settings to `.env.local`:

```env
GITHUB_TOKEN=...
GITLAB_TOKEN=...
CODEBERG_TOKEN=...
DATABASE_URL=sqlite://db/polish_open_source_rank.sqlite3
REQUESTS_PER_MINUTE=60
HTTP_OPEN_TIMEOUT=5
HTTP_READ_TIMEOUT=30
HTTP_WRITE_TIMEOUT=30
NPM_REGISTRY_REQUESTS_PER_MINUTE=30
RUBYGEMS_REGISTRY_REQUESTS_PER_MINUTE=20
CRATES_REGISTRY_REQUESTS_PER_MINUTE=10
PYPI_REGISTRY_REQUESTS_PER_MINUTE=20
HEX_REGISTRY_REQUESTS_PER_MINUTE=20
PACKAGIST_REGISTRY_REQUESTS_PER_MINUTE=20
GO_REGISTRY_REQUESTS_PER_MINUTE=20
BASE_URL=https://polish-open-source.pl
APP_BASE_PATH=/
```

`GITLAB_TOKEN` and `CODEBERG_TOKEN` are optional for public API access, but they
make monthly runs more stable.

## Quality

```sh
bin/quality
```

This runs RuboCop, Reek, Bundler Audit, and RSpec. SimpleCov enforces 100% line
coverage for `lib/**/*.rb`. CI also runs `bundle exec bundle-audit check
--update` and CodeQL before deploy.

In sandboxed or non-interactive shells, prefer repo entrypoints such as
`bin/bundle`, `bin/rspec`, and `bin/rake` instead of plain `bundle exec ...`.
That keeps commands on the project's pinned Ruby even when the shell PATH falls
back to `/usr/bin/bundle`.

Use `bin/gh` for GitHub CLI operations because Codex shells may omit Homebrew
from `PATH`. Authentication, pull request merge policy, and Actions inspection
are documented in [GitHub Operations](github-operations.md).

Mutation checks are available on demand through [Mutant](https://github.com/mbj/mutant):

```sh
bin/mutant-changed
```

That command mutation-tests changed domain and application subjects under
`lib/polish_open_source_rank` since `HEAD`. Set `MUTANT_SINCE` to compare
against another revision. Full Mutant output is written to `tmp/mutant-last.log`.

Pre-commit hooks live in `.githooks/pre-commit`. This checkout is configured
with:

```sh
git config core.hooksPath .githooks
```

## Local Operations Commands

Equivalent rake tasks are available for local job operations:

```sh
bin/rake crawl:monthly[2026-04,github,organizations,false]
bin/rake crawl:packages[2026-04,npm,100,false]
bin/rake crawl:packages[2026-04,npm,,false,5000,5000,10000,10000]
bin/rake crawl:repair_packages[2026-04]
bin/rake crawl:resume
bin/rake crawl:list
```
