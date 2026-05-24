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

1. [ ] Packagist downloads
2. [ ] Hex diagnosis
3. [ ] Homebrew
4. [ ] NuGet
5. [ ] Maven

## 1. Packagist Downloads

Dlaczego: dane Packagist już są w bazie, ale ekosystem nie jest widoczny, bo obecny klient nie zapisuje liczbowej metryki rankingowej.

- [ ] Sprawdzić oficjalny endpoint Packagist z metrykami downloads dla pakietu.
- [ ] Rozszerzyć `PackagistRegistryClient`, żeby zapisywał:
  - [ ] `downloads_total`,
  - [ ] `downloads_30d` albo najbliższy wiarygodny odpowiednik miesięczny, jeśli API go daje.
- [ ] Dodać `packagist` do publicznych metryk w `PackageRankingMetric`.
- [ ] Upewnić się, że `/packages` pokazuje Packagist po pojawieniu się snapshotów z metryką.
- [ ] Dodać testy dla klienta registry i ranking read modelu.
- [ ] Uruchomić package crawl dla Packagist lub pełny crawl z obecnymi limitami.
- [ ] Sprawdzić produkcyjne liczby snapshotów i pozycje rankingowe.

Definition of Done:

- [ ] Packagist jest widoczny w `/packages`.
- [ ] Ranking Packagist sortuje po prawdziwej metryce downloads.
- [ ] Brak metryki w API nie tworzy fałszywych zer.

## 2. Hex Diagnosis

Dlaczego: Hex ma już obsługiwaną metrykę `downloads_total` i jest dopuszczony w `PackageRankingMetric`, ale produkcja nie pokazuje Hex, bo nie ma aktywnych snapshotów.

- [ ] Sprawdzić produkcyjne `registry_packages` dla `hex`: statusy `active`, `not_found`, `failed`, `pending`.
- [ ] Sprawdzić `package_manifests` dla `hex`: `parsed`, `partial`, `failed`, `unpublished`.
- [ ] Ustalić, czy problemem są:
  - [ ] nazwy pakietów z parserów `mix.exs` / `rebar.config`,
  - [ ] błędne mapowanie do Hex API,
  - [ ] brak opublikowanych pakietów,
  - [ ] rate limiting albo błędy registry.
- [ ] Dodać brakujące testy regresyjne dla wykrytego przypadku.
- [ ] Naprawić parser albo klienta registry, jeśli diagnoza wskaże błąd po naszej stronie.
- [ ] Uruchomić ograniczony crawl Hex.

Definition of Done:

- [ ] Wiemy, dlaczego Hex nie pojawia się w UI.
- [ ] Jeśli mamy realne aktywne paczki Hex, `/packages` pokazuje Hex.
- [ ] Jeśli nie mamy realnych aktywnych paczek, mamy udokumentowaną przyczynę w testach lub diagnostyce.

## 3. Homebrew

Dlaczego: to najlepszy pierwszy systemowy ekosystem. Ma publiczne dane formuł i analytics, a wiele formuł mapuje się na repozytoria GitHub.

- [ ] Dodać nowy ekosystem `homebrew`.
- [ ] Dodać detekcję manifestów/formuł:
  - [ ] `Formula/*.rb`,
  - [ ] `Casks/*.rb`, jeśli zdecydujemy objąć caski,
  - [ ] lokalne tapy Homebrew, jeśli występują w polskich repozytoriach.
- [ ] Zaprojektować parser formuły jako bezpieczny parser statyczny, bez wykonywania Ruby.
- [ ] Wyciągać co najmniej:
  - [ ] nazwę formuły,
  - [ ] homepage,
  - [ ] URL źródłowy,
  - [ ] GitHub URL, jeśli występuje,
  - [ ] licencję, jeśli łatwo dostępna.
- [ ] Dodać klienta Homebrew analytics dla metryk:
  - [ ] installs 30d,
  - [ ] installs 90d albo total, jeśli potrzebne.
- [ ] Zmapować metrykę na `downloads_30d` albo osobną nazwę domenową, jeśli `downloads` byłoby mylące.
- [ ] Dodać ranking publiczny Homebrew.
- [ ] Dodać testy parsera, klienta analytics i read modelu.

Definition of Done:

- [ ] Homebrew ma stabilny ranking publiczny.
- [ ] Nie wykonujemy kodu formuł.
- [ ] Metryka jest nazwana tak, żeby nie mylić install analytics z registry downloads.

## 4. NuGet

Dlaczego: duży ekosystem .NET/C#, z publicznym registry API i licznikami pobrań.

- [ ] Dodać nowy ekosystem `nuget`.
- [ ] Dodać detekcję manifestów:
  - [ ] `.csproj`,
  - [ ] `.fsproj`,
  - [ ] `.vbproj`,
  - [ ] `.nuspec`,
  - [ ] `Directory.Packages.props`.
- [ ] Dodać parser:
  - [ ] package id,
  - [ ] version,
  - [ ] repository URL,
  - [ ] project URL,
  - [ ] license.
- [ ] Dodać klienta NuGet registry:
  - [ ] latest version,
  - [ ] downloads total,
  - [ ] registry URL,
  - [ ] repository/project URL, jeśli API daje.
- [ ] Dodać metrykę rankingową dla NuGet.
- [ ] Dodać testy XML parserów bez zależności od frameworków webowych.
- [ ] Uruchomić ograniczony crawl NuGet.

Definition of Done:

- [ ] NuGet jest widoczny w `/packages`.
- [ ] `.csproj` i `.nuspec` nie wymagają wykonywania build tooli.
- [ ] Ranking używa prawdziwych liczników NuGet.

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

- [ ] Uruchomić `bin/quality`.
- [ ] Wdrożyć po przejściu hooków.
- [ ] Sprawdzić `/packages`.
- [ ] Sprawdzić produkcyjne liczby:
  - [ ] `package_repository_scans`,
  - [ ] `package_manifests`,
  - [ ] `registry_packages`,
  - [ ] `registry_package_snapshots`,
  - [ ] statusy `active`, `not_found`, `failed`, `rate_limited`, `pending`.
- [ ] Sprawdzić `/internal/jobs` po crawl runie.
- [ ] Zanotować, czy ekosystem ma publiczny ranking, czy tylko diagnostykę.
