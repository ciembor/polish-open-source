# Backlog: rozszerzenie rankingów pakietów

Cel: pokazać więcej sensownych ekosystemów pakietów w publicznym `/packages`, ale tylko wtedy, gdy mamy wiarygodną metrykę rankingową albo świadomie oznaczony etap diagnostyczny. GitHub pozostaje źródłem kwalifikacji polskości; registry i systemy pakietów służą do metryk, wersji i linków.

## Zasady

- [ ] Nie klasyfikować pakietu jako polskiego na podstawie registry.
- [ ] Pakiet trafia do polskiego rankingu przez manifest w repozytorium zakwalifikowanym przez GitHubowy ranking PL.
- [ ] Nie pokazywać publicznego rankingu ekosystemu bez stabilnej metryki sortowania.
- [ ] Zachowywać `nil` dla niedostępnych metryk zamiast udawać zero.
- [ ] Każdy nowy ekosystem ma testy parsera, klienta registry, read modelu i UI/routingu.
- [ ] Każda zmiana przechodzi `bin/quality` i jest commitowana bez omijania hooków.

## Kolejność

1. [x] Packagist downloads
2. [x] Hex diagnosis
3. [x] Homebrew
4. [x] NuGet
5. [ ] Maven

## 1. Packagist Downloads

Dlaczego: dane Packagist już są w bazie, ale ekosystem nie jest widoczny, bo obecny klient nie zapisuje liczbowej metryki rankingowej.

- [x] Sprawdzić oficjalny endpoint Packagist z metrykami downloads dla pakietu.
- [x] Rozszerzyć `PackagistRegistryClient`, żeby zapisywał:
  - [x] `downloads_total`,
  - [x] `downloads_30d` albo najbliższy wiarygodny odpowiednik miesięczny, jeśli API go daje.
- [x] Dodać `packagist` do publicznych metryk w `PackageRankingMetric`.
- [x] Upewnić się, że `/packages` pokazuje Packagist po pojawieniu się snapshotów z metryką.
- [x] Dodać testy dla klienta registry i ranking read modelu.
- [x] Uruchomić package crawl dla Packagist lub pełny crawl z obecnymi limitami.
- [x] Sprawdzić produkcyjne liczby snapshotów i pozycje rankingowe.

Definition of Done:

- [x] Packagist jest widoczny w `/packages`.
- [x] Ranking Packagist sortuje po prawdziwej metryce downloads.
- [x] Brak metryki w API nie tworzy fałszywych zer.

Wynik produkcji: Packagist ma publiczny ranking. Refresh `2026-04` zapisał 188 aktywnych snapshotów z `downloads_total` i `downloads_30d`; top po miesięcznych pobraniach zaczyna się od `symfony/polyfill-mbstring`, `guzzlehttp/psr7`, `psr/http-message`.

## 2. Hex Diagnosis

Dlaczego: Hex ma już obsługiwaną metrykę `downloads_total` i jest dopuszczony w `PackageRankingMetric`, ale produkcja nie pokazuje Hex, bo nie ma aktywnych snapshotów.

- [x] Sprawdzić produkcyjne `registry_packages` dla `hex`: statusy `active`, `not_found`, `failed`, `pending`.
- [x] Sprawdzić `package_manifests` dla `hex`: `parsed`, `partial`, `failed`, `unpublished`.
- [x] Ustalić, czy problemem są:
  - [x] nazwy pakietów z parserów `mix.exs` / `rebar.config`,
  - [x] błędne mapowanie do Hex API,
  - [x] brak opublikowanych pakietów,
  - [x] rate limiting albo błędy registry.
- [x] Dodać brakujące testy regresyjne dla wykrytego przypadku.
- [x] Naprawić parser albo klienta registry, jeśli diagnoza wskaże błąd po naszej stronie.
- [x] Uruchomić ograniczony crawl Hex.

Definition of Done:

- [x] Wiemy, dlaczego Hex nie pojawia się w UI.
- [x] Jeśli mamy realne aktywne paczki Hex, `/packages` pokazuje Hex.
- [x] Jeśli nie mamy realnych aktywnych paczek, mamy udokumentowaną przyczynę w testach lub diagnostyce.

Wynik produkcji: problemem była normalizacja nazw w parserach `mix.exs` i `rebar.config`; zamienialiśmy `_` na `-`, podczas gdy Hex używa nazw z underscore. Po poprawce i celowanym refreshu `2026-04` Hex ma 42 aktywne snapshoty z `downloads_total`, 35 `not_found`, 0 `rate_limited`, 0 `failed`. Publiczny ranking jest widoczny w `/packages`; top po pobraniach zaczyna się od `money`, `req`, `mockery`.

## 3. Homebrew

Dlaczego: to najlepszy pierwszy systemowy ekosystem. Ma publiczne dane formuł i analytics, a wiele formuł mapuje się na repozytoria GitHub.

- [x] Dodać nowy ekosystem `homebrew`.
- [x] Dodać detekcję manifestów/formuł:
  - [x] `Formula/*.rb`,
  - [x] `Casks/*.rb`, jeśli zdecydujemy objąć caski: decyzja, nie mieszać casków z formułami w tym etapie,
  - [x] lokalne tapy Homebrew, jeśli występują w polskich repozytoriach.
- [x] Zaprojektować parser formuły jako bezpieczny parser statyczny, bez wykonywania Ruby.
- [x] Wyciągać co najmniej:
  - [x] nazwę formuły,
  - [x] homepage,
  - [x] URL źródłowy,
  - [x] GitHub URL, jeśli występuje,
  - [x] licencję, jeśli łatwo dostępna.
- [x] Dodać klienta Homebrew analytics dla metryk:
  - [x] installs 30d,
  - [x] installs 90d albo total, jeśli potrzebne.
- [x] Zmapować metrykę na `downloads_30d` albo osobną nazwę domenową, jeśli `downloads` byłoby mylące.
- [x] Dodać ranking publiczny Homebrew.
- [x] Dodać testy parsera, klienta analytics i read modelu.

Definition of Done:

- [x] Homebrew ma stabilny ranking publiczny.
- [x] Nie wykonujemy kodu formuł.
- [x] Metryka jest nazwana tak, żeby nie mylić install analytics z registry downloads.

Wynik implementacji: Homebrew obsługuje formuły `Formula/*.rb` także w lokalnych tapach (`*/Formula/*.rb`). Caski nie są mieszane z formułami w tym etapie, bo mają osobną kategorię analytics. Parser jest statyczny i nie wykonuje Ruby; klient czyta `formulae.brew.sh/api/formula/*.json`, zapisuje 30-dniowe instalacje w polu rankingowym `downloads_30d`, a UI pokazuje je jako „Instalacje 30 dni” / „30-day installs”.

## 4. NuGet

Dlaczego: duży ekosystem .NET/C#, z publicznym registry API i licznikami pobrań.

- [x] Dodać nowy ekosystem `nuget`.
- [x] Dodać detekcję manifestów:
  - [x] `.csproj`,
  - [x] `.fsproj`,
  - [x] `.vbproj`,
  - [x] `.nuspec`,
  - [x] `Directory.Packages.props`.
- [x] Dodać parser:
  - [x] package id,
  - [x] version,
  - [x] repository URL,
  - [x] project URL,
  - [x] license.
- [x] Dodać klienta NuGet registry:
  - [x] latest version,
  - [x] downloads total,
  - [x] registry URL,
  - [x] repository/project URL, jeśli API daje.
- [x] Dodać metrykę rankingową dla NuGet.
- [x] Dodać testy XML parserów bez zależności od frameworków webowych.
- [ ] Uruchomić ograniczony crawl NuGet.

Definition of Done:

- [x] NuGet jest widoczny w `/packages`.
- [x] `.csproj` i `.nuspec` nie wymagają wykonywania build tooli.
- [x] Ranking używa prawdziwych liczników NuGet.

Wynik implementacji: NuGet ma publiczny ranking po `downloads_total` z NuGet SearchQueryService. Klient odkrywa endpoint wyszukiwania przez service index NuGet V3, a parser XML statycznie obsługuje `.csproj`, `.fsproj`, `.vbproj`, `.nuspec` i diagnostycznie `Directory.Packages.props` bez uruchamiania build tooli. Ograniczony crawl produkcyjny pozostaje krokiem operacyjnym po wdrożeniu.

## 5. Maven

Dlaczego: ważny ekosystem JVM/Java/Kotlin, ale metryki popularności są mniej proste niż w Packagist/NuGet.

- [ ] Dodać decyzję produktową: czy Maven pokazujemy od razu publicznie, czy najpierw zbieramy dane diagnostycznie.
- [ ] Dodać nowy ekosystem `maven`.
- [ ] Dodać detekcję manifestów:
  - [ ] `pom.xml`,
  - [ ] `build.gradle`,
  - [ ] `build.gradle.kts`,
  - [ ] `settings.gradle`,
  - [ ] `settings.gradle.kts`.
- [ ] Dodać parser Maven/Gradle:
  - [ ] `groupId`,
  - [ ] `artifactId`,
  - [ ] version,
  - [ ] URL projektu,
  - [ ] SCM URL,
  - [ ] licencja.
- [ ] Dodać klienta Maven Central:
  - [ ] latest version,
  - [ ] artifact coordinates,
  - [ ] registry URL.
- [ ] Sprawdzić dostępne metryki popularności Maven Central.
- [ ] Jeśli nie ma dobrej metryki downloads, nie pokazywać publicznego rankingu Maven na siłę.
- [ ] Dodać widok diagnostyczny lub wewnętrzny raport liczby wykrytych artefaktów Maven.

Definition of Done:

- [ ] Maven artefakty są wykrywane i rozwiązywane do Maven Central.
- [ ] Publiczny ranking pojawia się tylko, jeśli mamy stabilną metrykę.
- [ ] Brak metryki jest jawnie opisany w kodzie/testach, nie ukryty w pustym UI.

## Operacje Po Każdym Etapie

- [x] Uruchomić `bin/quality`.
- [x] Wdrożyć po przejściu hooków.
- [x] Sprawdzić `/packages`.
- [x] Sprawdzić produkcyjne liczby:
  - [x] `package_repository_scans`,
  - [x] `package_manifests`,
  - [x] `registry_packages`,
  - [x] `registry_package_snapshots`,
  - [x] statusy `active`, `not_found`, `failed`, `rate_limited`, `pending`.
- [x] Sprawdzić `/internal/jobs` po crawl runie.
- [x] Zanotować, czy ekosystem ma publiczny ranking, czy tylko diagnostykę.
