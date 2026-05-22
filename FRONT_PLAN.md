# Front Plan: SEO, indeksacja PL/EN, metadata i jakość HTML5

Ten plan skupia się na tym, żeby aplikacja:

- dobrze się indeksowała w Google i innych wyszukiwarkach,
- poprawnie rozdzielała treść polską i angielską,
- dawała lepsze wyniki w SERP-ach, nie tylko przez pozycję, ale też przez lepszy snippet,
- miała bardziej przewidywalny, semantyczny HTML5,
- zachowała obecną architekturę aplikacji i nie wpychała logiki SEO do domeny.

## Główna diagnoza

Największy obecny problem nie leży w samych opisach SEO, tylko w architekturze locale:

- wersja językowa jest wybierana przez `?lang=` i cookie,
- canonical nie rozróżnia wersji PL i EN,
- obie wersje treści mogą kanonizować się do tego samego URL,
- wyszukiwarka widzi jedną stronę z dwoma wariantami języka zamiast dwóch poprawnie opisanych odpowiedników.

Dopóki to nie zostanie naprawione, reszta optymalizacji będzie miała ograniczony efekt.

## Cele

- Polska treść ma być domyślnie indeksowana jako główna wersja serwisu.
- Angielska treść ma być osobną, równorzędną alternatywą, a nie konkurującym wariantem pod tym samym adresem.
- Każda indeksowalna strona ma mieć poprawny:
  - URL,
  - canonical,
  - `hreflang`,
  - `title`,
  - `description`,
  - `og:*`,
  - `twitter:*`,
  - JSON-LD,
  - semantyczny HTML.

## Zasady wdrożenia

- SEO i locale to warstwa web/presentation, nie domena.
- Nie opierać indeksowalnych wersji stron na cookie.
- Każda ważna decyzja indeksacyjna ma być widoczna w URL, nie w stanie sesji.
- Dla crawlera ma istnieć jeden jednoznaczny URL na jedną wersję językową strony.
- Najpierw naprawić architekturę URL-i i canonicali, potem dopiero dopieszczać metadata i schema.

## Etap 1: architektura URL-i językowych

### Cel

Rozdzielić polskie i angielskie strony na osobne, stabilne adresy.

### Plan

- [x] Wprowadzić jawny routing językowy.
- [x] Przyjąć jedną z dwóch strategii:
  - wariant preferowany SEO-first:
    - polski pod obecnymi adresami, np. `/latest`,
    - angielski pod prefiksem `/en/...`;
  - wariant alternatywny:
    - `/pl/...` i `/en/...` dla obu języków.
- [x] Zostawić `?lang=` tylko jako mechanizm przejściowy.
- [x] Dodać przekierowania 301 z `?lang=en` i `?lang=pl` na docelowe ścieżki językowe.
- [x] Przestać używać cookie jako głównego źródła wyboru treści dla indeksowalnych stron.
- [x] Ustawić polski jako domyślny język publicznych stron.

### Uzasadnienie

To jest warunek konieczny, żeby Google nie sklejał PL i EN w jedną stronę i nie wybierał przypadkowo wersji angielskiej jako dominującej.

## Etap 2: canonical i `hreflang`

### Cel

Każda wersja językowa ma mieć własny canonical i poprawnie wskazanego odpowiednika.

### Plan

- [x] Przebudować helper budujący canonical tak, żeby brał pod uwagę język strony.
- [x] Dodać do `<head>` komplet linków alternatywnych:
  - [x] `hreflang="pl"`
  - [x] `hreflang="en"`
  - [x] `hreflang="x-default"`
- [x] Zapewnić, że każda podstrona ma alternatywę językową o tej samej semantyce:
  - [x] ranking Polski,
  - [x] ranking miasta,
  - [x] top/trending/active,
  - [x] profil użytkownika,
  - [x] profil repo,
  - [x] editions,
  - [x] about.
- [x] Wykluczyć sytuacje, w których EN kanonizuje się do PL albo odwrotnie.

### Uzasadnienie

Bez tego wyszukiwarka dalej będzie zgadywać, który wariant pokazać i który indeksować mocniej.

## Etap 3: metadata pod wynik w wyszukiwarce

### Cel

Poprawić wygląd wyniku w wyszukiwarce i spójność opisu strony.

### Plan

- [ ] Dopracować `title` dla wszystkich głównych typów stron:
  - [x] homepage/rankings,
  - [x] ranking city,
  - [x] ranking detail,
  - [x] user profile,
  - [x] repository profile,
  - [x] editions,
  - [x] about.
- [x] Dopracować `meta description` osobno dla PL i EN.
- [x] Pilnować, żeby opisy były:
  - konkretne,
  - krótkie,
  - bez duplikatów,
  - zgodne z intencją strony.
- [x] Ujednolicić wzorce generowania tytułów i opisów w kontrolerach publicznych.
- [x] Dodać testy regresyjne dla title/description/canonical na najważniejszych stronach.

### Uwaga

Trzeba pilnować, żeby copy SEO nie było zbyt generyczne. Obecnie jest poprawne technicznie, ale część opisów jest jeszcze zbyt mało charakterystyczna.

## Etap 4: Open Graph i Twitter Cards

### Cel

Poprawić prezentację linków w Google, Slacku, X, Discordzie i innych miejscach, które czytają metadata społecznościowe.

### Plan

- [x] Dodać:
  - [x] `og:title`
  - [x] `og:description`
  - [x] `og:url`
  - [x] `og:type`
  - [x] `og:image`
  - [x] `og:site_name`
  - [x] `og:locale`
- [x] Dodać:
  - [x] `twitter:card`
  - [x] `twitter:title`
  - [x] `twitter:description`
  - [x] `twitter:image`
- [x] Wybrać i ustabilizować główne obrazy preview:
  - [x] ranking page,
  - [x] about,
  - [x] editions,
  - [x] profile/repository fallback.
Future:
- [ ] Jeśli będzie to opłacalne, w kolejnym kroku dodać bardziej dynamiczne obrazy OG dla profili i repo.

## Etap 5: sitemap i robots

### Cel

Dać crawlerom jednoznaczną mapę indeksowalnych zasobów.

### Plan

- [x] Dodać `robots.txt`.
- [x] Umieścić w nim link do `sitemap.xml`.
- [x] Dodać `sitemap.xml` generowaną z aktualnych tras publicznych.
- [x] Umieścić w sitemap:
  - [x] strony PL,
  - [x] strony EN,
  - [x] `lastmod`,
  - [x] wszystkie główne publiczne widoki.
- [x] Rozważyć oddzielne sitemap dla:
  - na tym etapie zostaje jedna sitemap, bo obecny rozmiar i zakres danych tego nie wymagają.

### Uwaga

Jeśli profile użytkowników i repozytoriów są liczne, trzeba ustalić, czy wszystkie mają być w sitemap, czy tylko te z publicznego rankingu bieżącego okresu.

## Etap 6: structured data

### Cel

Ulepszyć zrozumienie typu strony przez wyszukiwarkę.

### Stan obecny

- [x] obecnie jest jedno proste JSON-LD typu `Dataset`. Zostało już zastąpione bardziej szczegółowym schematem per widok.

### Plan

- [x] Rozdzielić structured data zależnie od typu strony:
  - [x] `WebSite` dla serwisu,
  - [x] `CollectionPage` dla rankingów i editions,
  - [x] `ItemList` dla list rankingowych,
  - [x] `ProfilePage` dla user/repository pages,
  - [x] `BreadcrumbList` dla wszystkich głównych publicznych stron.
- [x] Nie generować jednego generycznego JSON-LD dla wszystkich stron.
- [x] Dodać helpery/presentery po stronie web, nie w domenie.
- [x] Utrzymać dane strukturalne spójne z canonicalem i locale.

## Etap 7: jakość HTML5 i semantyka

### Cel

Podnieść jakość dokumentu HTML bez robienia z tego kosmetycznego refaktoru.

### Plan

- [ ] Sprawdzić, czy każda strona ma dokładnie jedno `h1`.
- [ ] Uporządkować hierarchię `h1`/`h2`/`h3`.
- [ ] Przejrzeć semantykę list rankingowych:
  - [ ] czy powinny być listą,
  - [ ] czy w części przypadków lepsza byłaby tabela,
  - [ ] czy obecna struktura jest spójna dla accessibility i parserów.
- [ ] Uzupełnić sensowne `alt` dla obrazów dekoracyjnych i znaczących.
- [ ] Upewnić się, że elementy nawigacyjne mają poprawne `aria-label`.
- [ ] Unikać duplikowania znaczeń przez zbędne wrappery.
- [ ] Dodać walidację jakości HTML do checklisty review.

## Etap 8: treść PL i EN

### Cel

Polska i angielska wersja mają być kompletne i naturalne, a nie tylko technicznie przetłumaczone.

### Plan

- [ ] Przejrzeć wszystkie teksty SEO w `pl.yml` i `en.yml`.
- [ ] Dla każdej ważnej strony mieć osobne, sensowne:
  - [ ] title,
  - [ ] description,
  - [ ] hero copy,
  - [ ] ewentualne stałe nagłówki sekcji.
- [ ] Upewnić się, że polski content nie zawiera angielskich wstawek tam, gdzie nie powinien.
- [ ] Upewnić się, że EN nie jest kalką PL, jeśli brzmi nienaturalnie.
- [ ] Przejrzeć brand text i nazewnictwo:
  - `Polish Open Source`,
  - `open-source ranking`,
  - profile,
  - editions,
  - badges.

## Etap 9: linkowanie wewnętrzne

### Cel

Nie mieszać sygnałów językowych i indeksacyjnych.

### Plan

- [x] Wszystkie linki wewnętrzne w PL mają prowadzić do PL URL-i.
- [x] Wszystkie linki wewnętrzne w EN mają prowadzić do EN URL-i.
- [x] Language switch ma prowadzić do odpowiednika tej samej strony, a nie tylko ustawiać stan.
- [x] Linki z menu, hero, profili, rankingów i editions mają zachowywać bieżący język.
- [x] Canonical, sitemap i linkowanie wewnętrzne mają mówić to samo.

## Etap 10: testy i weryfikacja

### Cel

Zabezpieczyć SEO przed przypadkowym regressem.

### Plan

- [ ] Dodać testy request/HTML dla:
  - [ ] PL canonical,
  - [ ] EN canonical,
  - [ ] `hreflang`,
  - [ ] `og:*`,
  - [ ] `twitter:*`,
  - [ ] `html lang`,
  - [ ] sitemap,
  - [ ] robots,
  - [ ] redirectów z `?lang=`.
- [ ] Dodać testy dla najważniejszych stron:
  - [ ] `/latest`,
  - [ ] city ranking,
  - [ ] ranking detail,
  - [ ] `/about`,
  - [ ] `/editions`,
  - [ ] user profile,
  - [ ] repository profile.
- [ ] Ręcznie sprawdzić wynik w:
  - [ ] Google Rich Results Test,
  - [ ] Open Graph debugger,
  - [ ] HTML validator.

## Etap 11: monitoring po wdrożeniu

### Cel

Zweryfikować, że zmiana naprawdę poprawiła indeksację.

### Plan

- [ ] Podpiąć i przejrzeć Google Search Console.
- [ ] Zgłosić sitemap.
- [ ] Monitorować:
  - [ ] pages indexed,
  - [ ] duplicate without user-selected canonical,
  - [ ] alternate page with proper canonical,
  - [ ] query impressions dla PL i EN.
- [ ] Sprawdzić, czy Google pokazuje polskie snippet-y dla polskich zapytań.
- [ ] Jeśli trzeba, poprosić o reindex po wdrożeniu nowej struktury URL-i.

## Proponowana kolejność realizacji

### Faza 1: naprawa fundamentu indeksacji

- [ ] URL-e językowe
- [ ] canonical per locale
- [ ] `hreflang`
- [ ] default locale = `pl`
- [ ] redirecty z `?lang=`

### Faza 2: sygnały dla crawlerów

- [ ] `robots.txt`
- [ ] `sitemap.xml`
- [ ] poprawa linkowania wewnętrznego

### Faza 3: lepszy snippet i preview

- [ ] `og:*`
- [ ] `twitter:*`
- [ ] lepsze title/description

### Faza 4: semantyka i dane strukturalne

- [ ] JSON-LD per typ strony
- [ ] breadcrumbs
- [ ] HTML5 cleanup

### Faza 5: testy i monitoring

- [ ] testy regresyjne
- [ ] Search Console
- [ ] walidacja snippetów i indeksacji

## Kryteria zakończenia

- [ ] PL i EN mają osobne, stabilne URL-e.
- [ ] Każda wersja językowa ma własny canonical i `hreflang`.
- [ ] Polska wersja jest domyślną wersją publiczną serwisu.
- [ ] Publiczne strony mają pełny zestaw metadata pod SEO i preview.
- [ ] `robots.txt` i `sitemap.xml` działają.
- [ ] Structured data jest zależne od typu strony, nie globalnie generyczne.
- [ ] Najważniejsze widoki przechodzą testy SEO/locale.
- [ ] Search Console nie pokazuje konfliktów canonical/alternate dla PL i EN.
