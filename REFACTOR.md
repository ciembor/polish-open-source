# Refactor Milestones

This file tracks refactors that should reduce long-term complexity, not just
move code around. Mark a task done only after the change is implemented,
covered where useful, checked by the quality gate, and committed when the
milestone is complete.

## Milestone 1: Decouple OAuth Login Flow From Sinatra

Goal: keep Sinatra routes as request/response adapters while OAuth login
decisions live in a plain, testable flow object.

- [x] Replace the old refactor notes with current milestones.
- [x] Add an OAuth login flow object with explicit collaborators and result
      objects.
- [x] Move GitHub callback profile registration and session construction out
      of `Routes::AuthFlow`.
- [x] Move Discord token exchange and account connection decisions out of
      `Routes::AuthFlow`.
- [x] Simplify `Routes::AuthFlow` so it owns session state, redirects, and
      Sinatra-only concerns.
- [x] Add focused contract specs for the OAuth login flow.
- [x] Run the full pre-commit hook and commit the completed milestone.

## Milestone 2: Finish Configuration Boundary Cleanup

Goal: make `Configuration` a stable public API while volatile env definition
and parsing details live below it.

- [x] Move raw setting definitions into a dedicated definition object or module.
- [x] Keep legacy getters stable while grouping related settings behind deeper
      value objects.
- [x] Add tests for required, optional, defaulted, and transformed env values.
- [x] Verify Reek stays clean without suppressions.
- [x] Run the full pre-commit hook and commit the completed milestone.

## Milestone 3: Strengthen Auth And Session Contracts

Goal: make auth state transitions explicit and hard to misuse.

- [ ] Introduce small request/result models for OAuth callback inputs and
      outcomes where that removes hash or session reconstruction.
- [ ] Keep OAuth state validation in the web adapter, but document the contract
      expected by the login flow.
- [ ] Add focused specs for replay, missing code, missing current user, and
      retry-message behavior.
- [ ] Run the full pre-commit hook and commit the completed milestone.

## Milestone 4: Reduce Web Composition Growth

Goal: keep web composition semantic instead of turning it into a generic service
locator.

- [ ] Review web composition methods by bounded context and use case.
- [ ] Group only collaborators that hide real construction or vendor detail.
- [ ] Add architecture specs if a new composition boundary is introduced.
- [ ] Update `docs/web-app.md` when the composition contract changes.
- [ ] Run the full pre-commit hook and commit the completed milestone.

## Milestone 5: Localize SQLite Knowledge

Goal: keep table and column knowledge inside repository/read-model adapters.

- [ ] Find callers that still know SQLite column names or table shape outside
      infrastructure.
- [ ] Move repeated SQL fragments behind semantic read-model methods.
- [ ] Add regression specs before touching published ranking, profile, badge,
      or package queries.
- [ ] Run the full pre-commit hook and commit the completed milestone.

## Milestone 6: Documentation And Operational Follow-Through

Goal: keep architecture and security boundaries understandable after code
changes.

- [ ] Update security documentation for internal endpoints, app-owned Basic
      Auth, CDN cache bypasses, OAuth, secrets, rate limiting, HSTS, and
      backups.
- [ ] Link security and architecture docs from the documentation index.
- [ ] Add a short guide for safely changing ranking methodology and publication
      behavior.
- [ ] Run the full pre-commit hook and commit the completed milestone.
