# Documentation

This directory is the canonical home for project documentation.

## Guides

- [Overview](overview.md): product scope, collected data, and ranking model.
- [Monthly Snapshot Architecture](monthly-snapshot.md): monthly ranking flow, collaborator responsibilities, and architecture guardrails.
- [SQLite Data Ownership](data-ownership.md): table ownership, shared read dependencies, and schema change conventions.
- [Development](development.md): local setup, quality checks, and day-to-day development commands.
- [GitHub Operations](github-operations.md): persistent CLI authentication, pull request and Dependabot triage, merge policy, and GitHub Actions incident handling.
- [Web App](web-app.md): local web server usage, public routes, Cloudflare purge, and cache expectations.
- [Crawl Jobs](crawl-jobs.md): monthly and package job behavior, production services, resume semantics, and server commands.
- [Deployment](deployment.md): production topology, GitHub Actions deploy flow, and one-step rollback behavior.
- [Publication](publication.md): public snapshot rules, Cloudflare purge after publish or rollback, historical metric semantics, and publication rollback.
- [Performance](performance.md): load profile, SLOs, query-plan checks, and spike response.
- [Operations Runbook](operations-runbook.md): Sentry and Cloudflare setup, incident handling, restarts, and backup restore steps.
- [User Actions](user-actions.md): request paths that write state or call external APIs.
