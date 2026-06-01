# Akcje użytkownika zapisujące stan albo wołające zewnętrzne API

## GitHub OAuth

- `GET /auth/github` zapisuje stan OAuth w sesji.
- `GET /auth/github/callback` woła GitHub OAuth token API i GitHub user API.
- Callback zapisuje sesję użytkownika.
- Dla kwalifikujących się profili spoza aktualnego snapshotu callback upsertuje publiczny profil w SQLite.

## Discord OAuth

- `GET /auth/discord` zapisuje stan OAuth w sesji.
- `GET /auth/discord/callback` woła Discord OAuth token API i Discord user API.
- Callback zapisuje połączenie Discord w SQLite.
- Callback zapisuje intencje `member_sync` i `welcome_message` w outboxie `discord_sync_jobs`.
- Callback nie wykonuje joinu do guilda, synchronizacji ról ani welcome message w requestcie użytkownika.

## Discord invite bot

- Event `member_join` odczytuje użyty invite z Discorda.
- Po rozpoznaniu invite zapisuje połączenie Discord w SQLite.
- Event zapisuje intencję `member_sync` w outboxie `discord_sync_jobs`.
- Bot może uruchomić procesor outboxa poza requestem HTTP.

## Sesja

- `POST /logout` czyści sesję po poprawnym tokenie CSRF.

## Operacyjne przetwarzanie outboxa

- `bin/discord_sync [limit]` przetwarza oczekujące i retryable zadania Discord.
- Zadania kończą ze statusem `pending`, `synced`, `failed` albo `retryable`.
- Ponowne kliknięcie Discord connect nadpisuje istniejące intencje dla profilu i rodzaju akcji zamiast tworzyć duplikaty.
