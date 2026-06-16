# User Actions That Write State or Call External APIs

## GitHub OAuth

- `GET /auth/github` stores OAuth state in the session.
- `GET /auth/github/callback` calls the GitHub OAuth token API and GitHub user
  API.
- The callback stores the user session.
- For qualifying profiles outside the current snapshot, the callback upserts a
  public profile into SQLite.

## Discord OAuth

- `GET /auth/discord` stores OAuth state in the session.
- `GET /auth/discord/callback` calls the Discord OAuth token API and Discord
  user API.
- The callback stores the Discord connection in SQLite.
- The callback stores `member_sync` and `welcome_message` intents in the
  `discord_sync_jobs` outbox.
- The Discord OAuth access token is kept only while a `member_sync` job is
  pending or retryable, then cleared when the job is synced or failed.
- The callback does not join the guild, sync roles, or send the welcome message
  inside the user request.

## Discord Invite Bot

- A `member_join` event reads the used invite from Discord.
- After a recognized invite, it stores the Discord connection in SQLite.
- The event stores a `member_sync` intent in `discord_sync_jobs`.
- The bot can run the outbox processor outside the HTTP request path.

## Session

- `POST /logout` clears the session after a valid CSRF token.

## Operational Outbox Processing

- `bin/discord_sync [limit]` processes pending and retryable Discord jobs.
- Discord OAuth callbacks sync the connected account immediately after storing
  the outbox jobs.
- Jobs finish with status `pending`, `synced`, `failed`, or `retryable`.
- Repeating the Discord connect flow overwrites existing intents for the same
  profile and action kind instead of creating duplicates.
