# Publikacja publicznego snapshotu

## Definicja opublikowanego miesiąca

Miesiąc jest publiczny dopiero wtedy, gdy ma wpis `published` albo `superseded`
w `public_snapshot_publications`. Status `published` oznacza bieżący `latest`,
a `superseded` oznacza starszy miesiąc, który nadal może być linkowany w historii,
sitemapach, canonicalach i `hreflang`.

Snapshot można opublikować, jeśli:

- monthly run w `sync_runs` ma status `finished`,
- istnieją dane publiczne dla users, repositories, organizations i organization repositories,
- dla tego miesiąca nie ma package crawl runów w statusie innym niż `finished`.

Languages są danymi pochodnymi z publicznych repozytoriów, więc publikują się razem z repository stats.
Badges, profile, rankingi, packages, languages, sitemap, canonicale i `hreflang` używają tylko opublikowanego miesiąca albo aliasu `latest`.

## Semantyka historycznych metryk

Dla GitHuba publiczne repozytoria i repozytoria organizacji zapisują dwie różne metryki miesięczne:

- `stargazers_count` oznacza liczbę gwiazdek na końcu publikowanego miesiąca,
- `monthly_stars_delta` oznacza tylko gwiazdki zdobyte w tym miesiącu według `starred_at`.

Dla GitLaba i Codeberga nie mamy dziś datowanej historii gwiazdek, więc:

- `stargazers_count` pozostaje wartością zaobserwowaną podczas monthly crawla,
- `monthly_stars_delta` jawnie zapisuje `0`, zamiast udawać historyczny diff.

Languages i packages nie liczą tych liczb osobno. Obie sekcje dołączają
`repository_monthly_stats` albo `organization_repository_monthly_stats` po tym samym
`period_start`, więc opublikowany miesiąc nie miesza danych repozytorium z innego okresu.

## Plan backfillu historycznych gwiazdek

Backfill dotyczy tylko miesięcy GitHuba, które były policzone przed wprowadzeniem
historycznych snapshotów albo zostały uruchomione z `--use-stars-diff`.

Szacowanie kosztu zaczyna się od prostego dolnego ograniczenia:

- co najmniej jedno żądanie historii stargazerów na repozytorium i miesiąc,
- czas minimalny `repo_count / REQUESTS_PER_MINUTE`,
- przy bieżącym `REQUESTS_PER_MINUTE=60` przykład z lokalnego snapshotu z `300`
  repozytoriami daje dolne ograniczenie około `5` minut na jeden miesiąc GitHuba,
  bez dodatkowych stron historii, retry i czekania na rate limit.

Kolejność wykonania:

1. Najstarszy opublikowany miesiąc bez historycznych gwiazdek.
2. Jeden miesiąc na uruchomienie, z możliwością resume po statusach w SQLite.
3. Wstrzymanie kolejnych miesięcy, jeśli Sentry pokaże wzrost retry, 5xx albo latency.

## Promocja

`bin/publish_snapshot YYYY-MM` wykonuje:

1. `staged` dla wskazanego miesiąca,
2. weryfikację warunków publikacji,
3. checkpoint WAL,
4. backup pliku SQLite do `db/publication_backups`,
5. atomową zmianę aktualnego `published` na `superseded` i nowego miesiąca na `published`.

Rollback nie dotyka danych roboczych:

```sh
bin/publish_snapshot --rollback
```

Rollback oznacza aktualny snapshot jako `rolled_back` i przywraca poprzedni `published`.

## Osobny snapshot do publicznego odczytu

Domyślnie web czyta publiczne strony z `DATABASE_URL`, żeby zachować kompatybilność z istniejącym jobem.
Po przygotowaniu osobnego pliku można ustawić:

```sh
PUBLIC_DATABASE_URL=sqlite://db/public.sqlite3
```

Wtedy publiczne read modele otwierają ten plik z `PRAGMA query_only = ON`, a user actions i job state nadal zapisują do `DATABASE_URL`.
