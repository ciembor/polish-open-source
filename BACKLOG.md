# Backlog: lepsze odkrywanie polskich pakietów

Cel: zwiększyć liczbę i jakość polskich pakietów w rankingach bez zmiany źródła prawdy o polskości. GitHub pozostaje źródłem atrybucji PL, a registry służą tylko do metryk popularności, wersji i trendów.

## Zasady produktu i danych

- [ ] GitHub jest źródłem prawdy dla polskości repozytorium, właściciela i organizacji.
- [ ] Registry nie klasyfikuje pakietu jako polskiego.
- [ ] Manifest w polskim repozytorium łączy GitHub repo z pakietem w registry.
- [ ] Registry wzbogaca znany polski pakiet o metryki, takie jak downloads, dependents, latest version i registry URL.
- [ ] Rankingi pakietów pozostają per ecosystem; nie dodajemy globalnego cross-ecosystem rankingu.
- [ ] Trending packages opierają się na delcie metryk registry, ale kwalifikacja do rankingu nadal pochodzi z GitHuba.

## Milestone 1 - szerokie inventory repozytoriów z GitHuba

- [ ] Potwierdzić, które tabele monthly snapshot już przechowują wszystkie publiczne repozytoria zaakceptowanych polskich userów i organizacji.
- [ ] Jeśli inventory jest obecnie zbyt wąskie, rozszerzyć monthly crawl tak, żeby zapisywał publiczne, niearchiwalne, nieforkowane repozytoria polskich właścicieli niezależnie od liczby gwiazdek.
- [ ] Zapisać lub udostępnić package crawlowi tanie pola priorytetyzacji: `stargazers_count`, `monthly_stars_delta`, `pushed_at`, `created_at`, `primary_language`, `topics`, `fork`, `archived`, `owner_kind`.
- [ ] Liczyć `monthly_stars_delta` domyślnie z poprzedniego lokalnego snapshotu, zamiast pytać GitHuba o historię gwiazdek dla każdego repozytorium.
- [ ] Zostawić droższe GitHub queries tylko dla przypadków, gdzie lokalny diff nie wystarcza i wartość danych uzasadnia koszt.
- [ ] Dodać testy, że niskogwiazdkowe repozytoria polskich właścicieli trafiają do inventory.

## Milestone 2 - nowa kolejka package scan

- [ ] Usunąć twardy filtr `stars >= 5 OR monthly_stars_delta > 0` jako warunek kwalifikacji do skanowania manifestów.
- [ ] Zastąpić go priorytetami kolejki:
  - [ ] priorytet 0: repozytoria już powiązane ze znanymi opublikowanymi pakietami,
  - [ ] priorytet 1: repozytoria z dodatnim `monthly_stars_delta`, świeżym `pushed_at` albo świeżym `created_at`,
  - [ ] priorytet 2: repozytoria package-like po języku, topics albo wcześniejszych manifestach,
  - [ ] priorytet 3: repozytoria z gwiazdkami powyżej niskiego progu,
  - [ ] priorytet 4: rotacyjna próbka długiego ogona.
- [ ] Zachować pomijanie forków i repozytoriów zarchiwizowanych.
- [ ] Dodać rotację długiego ogona, żeby repozytoria z małą liczbą gwiazdek były skanowane okresowo, ale nie blokowały całego joba.
- [ ] Zapisać powód enqueue i priorytet, żeby można było diagnozować, skąd wzięły się kandydaty.
- [ ] Dodać statystyki joba pokazujące liczbę repozytoriów per priorytet i status.

## Milestone 3 - cache manifestów między okresami

- [ ] Wykorzystać `tree_sha` jako klucz do pomijania skanowania niezmienionych repozytoriów między okresami.
- [ ] Upewnić się, że cache uwzględnia `parser_version`, żeby zmiana parserów wymusiła ponowne przeliczenie manifestów.
- [ ] Przenieść ponowne użycie manifestów do adaptera/repozytorium, nie do CLI.
- [ ] Przy braku zmian w tree kopiować lub materializować poprzednie wyniki manifestów dla nowego okresu.
- [ ] Dodać testy, że niezmienione repozytorium nie pobiera ponownie blobów manifestów.
- [ ] Dodać testy, że zmiana `parser_version` wymusza refresh.

## Milestone 4 - znane pakiety i snapshoty registry

- [ ] Co miesiąc odświeżać registry snapshots dla pakietów już powiązanych z polskimi repozytoriami, nawet jeśli repozytorium nie zostało ponownie zeskanowane.
- [ ] Nie usuwać pakietu z rankingu tylko dlatego, że w danym miesiącu repozytorium nie trafiło do budżetu scanów.
- [ ] Rozróżnić brak pakietu w registry od czasowego błędu registry.
- [ ] Zachowywać `nil` dla metryk niedostępnych, zamiast używać fałszywego zera.
- [ ] Dodać raport liczby aktywnych, not_found, failed i rate_limited pakietów per ecosystem.

## Milestone 5 - trending packages

- [ ] Dodać metryki trendu per ecosystem, bazujące na porównaniu bieżącego i poprzedniego snapshotu registry.
- [ ] Obsłużyć `downloads_30d_delta` dla npm i innych registry, które mają wiarygodne okno pobrań.
- [ ] Obsłużyć `downloads_total_delta` tam, gdzie dostępny jest tylko licznik total.
- [ ] Dodać minimalne progi bazowe, żeby nie promować szumu typu wzrost z 1 do 12 pobrań.
- [ ] Dodać per-ecosystem progi i sortowanie, zamiast jednego globalnego algorytmu dla wszystkich rejestrów.
- [ ] Dodać deterministyczne tie-breakery.
- [ ] Dodać publiczne lub wewnętrzne widoki trending dopiero po stabilizacji danych z co najmniej dwóch okresów.

## Milestone 6 - ostrożne package-first discovery

- [ ] Traktować registry metadata tylko jako źródło linków do GitHuba, nie jako dowód polskości.
- [ ] Jeśli registry wskazuje GitHub URL, mapować go do znanego GitHub inventory.
- [ ] Kwalifikować pakiet jako polski tylko wtedy, gdy repozytorium z registry URL przechodzi przez GitHubową klasyfikację PL.
- [ ] Oznaczać źródło odkrycia pakietu, np. `manifest_in_polish_repo`, `known_package_refresh`, `registry_source_url_match`.
- [ ] Nie dodawać GitHub Code Search jako głównego mechanizmu odkrywania manifestów.
- [ ] Dodać testy, że pakiet znaleziony w registry bez potwierdzonego polskiego repozytorium nie trafia do polskiego rankingu.

## Milestone 7 - wydajność i budżety jobów

- [ ] Nie zwiększać kosztu monthly crawl przez pełne skanowanie manifestów.
- [ ] Utrzymać package crawl jako osobny, wznawialny job.
- [ ] Dodać osobne limity dla enqueue, scan, manifest parsing, registry resolution i registry snapshot.
- [ ] Ustalić produkcyjne budżety tak, żeby high-priority repozytoria kończyły się w jednym przebiegu, a długi ogon rotował.
- [ ] Upewnić się, że przerwany job można wznowić bez utraty już zapisanych wyników.

## Milestone 8 - jakość danych i diagnostyka

- [ ] Dodać stronę lub log operacyjny pokazujący, dlaczego liczba pakietów w danym ecosystem jest niska.
- [ ] Raportować top przyczyny odrzucenia manifestów: private, unpublished, custom registry, parse failed, registry not found.
- [ ] Raportować repozytoria z manifestami bez opublikowanego pakietu.
- [ ] Raportować pakiety z metrykami registry, ale bez rankingowej metryki dla danego ecosystem.
- [ ] Dodać sanity checks po jobie: liczba scanów, manifestów, pakietów, snapshotów i rankingowych pozycji per ecosystem.

## Milestone 9 - architektura i testy

- [ ] Utrzymać regułę: use case’y packages nie importują szczegółów GitHuba, SQLite, registry ani web layer.
- [ ] Umieścić priorytetyzację kandydatów w aplikacyjnym use case albo domenowej polityce, nie w SQL rozproszonym po adapterach.
- [ ] Adapter SQLite może optymalizować zapytania, ale nie powinien być jedynym miejscem, gdzie da się zrozumieć reguły kwalifikacji.
- [ ] Dodać testy use case dla niskogwiazdkowego repozytorium z package manifestem i wysokimi downloads.
- [ ] Dodać testy trending z poprzednim i bieżącym snapshotem.
- [ ] Dodać testy regresyjne dla pakietów bez metryk, błędów registry i niezmienionego `tree_sha`.
- [ ] `bin/quality` przechodzi.
- [x] Zmiany są commitowane po przejściu hooków.

## Milestone 10 - operacyjny monitor jobów i estymacje czasu

Cel: `/internal/jobs` ma pomagać w decyzjach operacyjnych, np. ile potrwa zwiększenie liczby zapisywanych repozytoriów albo rozszerzenie package crawl. Monitor nie może mieszać userów, organizacji, repozytoriów i pakietów w jedną liczbę postępu.

- [x] Rozdzielić monitor na niezależne sekcje:
  - [x] monthly users,
  - [x] monthly organizations,
  - [x] user repositories,
  - [x] organization repositories,
  - [x] package repository scans,
  - [x] package manifests,
  - [x] registry packages,
  - [x] registry snapshots per ecosystem.
- [x] Dodać jawny model etapów joba, zamiast wyprowadzać wszystko pośrednio z `sync_runs`, `crawl_job_runs` i istniejących tabel rankingowych.
- [x] Notować zdarzenia przetwarzania w osobnej tabeli operacyjnej, np. `job_work_events`:
  - [x] `job_run_id` albo stabilny identyfikator runu,
  - [x] `period_start`,
  - [x] `job_kind`,
  - [x] `stage`,
  - [x] `unit_kind`,
  - [x] `platform`,
  - [x] `ecosystem`,
  - [x] `subject_id`,
  - [x] `subject_label`,
  - [x] `status`,
  - [x] `started_at`,
  - [x] `finished_at`,
  - [x] `duration_ms`,
  - [x] `error`.
- [x] Utrzymać istniejące tabele domenowe jako źródło prawdy dla wyników, a tabelę zdarzeń traktować jako obserwowalność/telemetrię.
- [x] Mierzyć osobno średni, medianowy i p95 czas:
  - [x] przetworzenia kandydata-usera,
  - [x] przetworzenia kandydata-organizacji,
  - [x] pobrania i zapisania repozytoriów usera,
  - [x] pobrania i zapisania repozytoriów organizacji,
  - [x] policzenia delty gwiazdek repozytorium,
  - [x] zeskanowania repozytorium packages,
  - [x] sparsowania manifestu,
  - [x] rozwiązania pakietu w registry,
  - [x] pobrania snapshotu registry package.
- [x] Dla każdego etapu pokazywać:
  - [x] total,
  - [x] done,
  - [x] pending,
  - [x] failed,
  - [x] skipped,
  - [x] throughput/min,
  - [x] średni czas/unit,
  - [x] medianę,
  - [x] p95,
  - [x] ETA według średniej i według p95.
- [x] Dla packages pokazywać osobne wiersze per ecosystem, żeby npm/crates/RubyGems/PyPI/Packagist/Go nie zasłaniały się nawzajem.
- [x] Dla package repository scans rozdzielić `repository_kind=user` i `repository_kind=organization`.
- [x] Dla registry snapshots rozdzielić statusy `active`, `not_found`, `rate_limited`, `failed`, `pending`.
- [x] Pokazywać, który stage jest aktualnie wykonywany i kiedy ostatnio przesunął licznik.
- [x] Dodać ostrzeżenie stale progress, jeśli dany etap nie ma nowych zdarzeń przez konfigurowalny czas.
- [x] Dodać linki lub drill-down do ostatnich błędów per stage i ecosystem.
- [x] Zachować `/internal/jobs` jako noindex/no-store i nie wystawiać danych operacyjnych do publicznych cache.
- [x] Dodać testy read modelu monitora bez realnej sieci.
- [x] Dodać testy, że scoped monthly jobs pokazują userów i organizacje niezależnie.
- [x] Dodać testy, że package job pokazuje metryki per ecosystem i per stage.
- [x] `bin/quality` przechodzi.
- [ ] Zmiany są commitowane po przejściu hooków.

## Proponowana kolejność wdrożenia

- [ ] PR 1: poszerzyć package queue o niskogwiazdkowe repozytoria z inventory, dodać priorytety i diagnostykę.
- [ ] PR 2: dodać cache manifestów między okresami po `tree_sha` i `parser_version`.
- [ ] PR 3: odświeżać znane pakiety niezależnie od ponownego skanowania repozytorium.
- [ ] PR 4: dodać trending metrics i ranking po deltach registry.
- [ ] PR 5: dodać ostrożne registry source URL matching do znanego GitHub inventory.
- [ ] PR 6: zoptymalizować monthly crawl pod lokalne diffy gwiazdek i szerokie repository inventory.
- [ ] PR 7: przebudować `/internal/jobs` na niezależne sekcje users/orgs/repos/packages z throughput i ETA.

## Definition of Done

- [ ] GitHub pozostaje jedynym źródłem kwalifikacji PL.
- [ ] Registry służy tylko do metryk i linków pomocniczych.
- [ ] Niskogwiazdkowe polskie repozytoria mogą trafić do package scan.
- [ ] Trending packages używają porównania snapshotów, a nie samych gwiazdek.
- [ ] Joby są wznawialne, limitowane i diagnozowalne.
- [ ] `/internal/jobs` pokazuje niezależny postęp i ETA dla userów, organizacji, repozytoriów oraz packages per ecosystem.
- [ ] Testy pokrywają decyzje kwalifikacji, cache, trendy i błędy registry.
- [ ] `bin/quality` przechodzi.
- [ ] Zmiany są zacommitowane po przejściu hooków.
