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
