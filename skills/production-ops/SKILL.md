---
name: production-ops
description: Use when a request involves production access, incident triage, deploy or rollback, service restarts, Podman containers, systemd units, journalctl logs, /internal/jobs, manual crawl operations, or production database inspection for Polish Open Source Rank. Read docs/deployment.md, docs/crawl-jobs.md, and docs/operations-runbook.md first; also read docs/publication.md for snapshot publication work and docs/performance.md for traffic or latency incidents.
---

# Production Ops

## Quick Orientation

- Production host: `ciembor@maciej-ciemborowicz.eu`
- Checkout path: `/home/ciembor/polish-open-source-rank`
- The app runs as systemd-managed Podman containers. Do not assume host-native app
  processes or direct host access to runtime state.
- Deploys and one-step rollbacks go through GitHub Actions. Do not invent a manual
  deploy path unless the user explicitly asks for emergency recovery work outside the
  normal flow.

## Read These Files First

Read only the files needed for the task:

- `docs/deployment.md`: production topology, GitHub Actions deploy flow, smoke checks,
  and one-step rollback behavior
- `docs/crawl-jobs.md`: production services, resume semantics, Podman usage, and
  manual crawl commands
- `docs/operations-runbook.md`: restarts, alert checks, incident workflow, and
  backup restore procedure
- `docs/publication.md`: publication and `publish_snapshot --rollback` tasks
- `docs/performance.md`: latency, traffic spikes, and SLO-oriented triage

## Default Workflow

1. Classify the task first:
   - deploy or rollback
   - web or bot restart
   - crawl, monthly, or packages triage
   - publication rollback
   - latency or incident investigation
2. Inspect before mutating:
   - SSH to the production host
   - Check running containers with
     `sudo podman ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'`
   - Check systemd units with `systemctl status ... --no-pager`
   - Check logs with `journalctl -u ...`
   - Check job state with `curl -fsS -u ciembor https://polish-open-source.pl/internal/jobs`
3. Choose the narrowest action that matches the problem:
   - web app: `polish-open-source-rank.service`
   - Discord bot: `polish-open-source-rank-discord-bot.service`
   - interrupted crawl recovery: `polish-open-source-rank-crawl-resume.service`
   - monthly snapshot job: `polish-open-source-rank-monthly.service`
   - package rankings job: `polish-open-source-rank-packages.service`
   - crawl loop: `polish-open-source-rank-crawl.service`
4. If database inspection is needed, inspect it from the app container context with
   `sudo podman exec -w /app polish-open-source-rank ...`, not with ad hoc host-side
   assumptions.
5. After any change, verify the relevant public endpoint, job state, or service status
   end to end.

## Guardrails

- Prefer observation over restart.
- Do not restart `monthly` or `packages` blindly. Check whether the job is active,
  progressing, or better resumed through `crawl-resume`.
- Use the GitHub Actions deploy workflow for normal deploys and the built-in one-step
  rollback for rollbacks.
- Treat `/internal/jobs`, systemd status, container status, and recent logs as
  the primary sources of truth before drawing conclusions. `/internal/jobs` is
  protected by nginx Basic Auth in production.
- Any destructive action or workaround that bypasses the documented deploy flow needs
  explicit user approval.

## Output Expectations

- State which host facts, units, containers, endpoints, and logs you inspected.
- State exactly what changed and why that action was chosen over broader restarts.
- Call out remaining risk, especially when a crawl is resumed, a rollback is pending,
  or smoke checks are incomplete.
