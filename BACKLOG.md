# Backlog produkcyjny

## Cel

Uodpornić serwis na większy ruch i równoległe akcje użytkowników bez ukrywania problemów pod ogólnym "retry". Priorytetem jest to, żeby publiczne strony nie kładły aplikacji, a logowanie, Discord i inne akcje zapisu kończyły się przewidywalnie nawet przy lockach SQLite, wolnych API zewnętrznych albo skokach ruchu.

## Priorytety

- `P0` - ryzyka, które mogą położyć stronę albo zablokować akcje użytkownika pod ruchem.
- `P1` - zmiany, które zmniejszają koszt operacyjny i ryzyko powrotu problemu.
- `P2` - poprawki jakości danych i długofalowa skalowalność.

## Zasady SEO dla wersji PL i EN

Te zasady obowiązują przy każdym milestone'u dotykającym cache, redirectów, routingu, publikacji danych, rate limitów albo publicznego HTML.

- [ ] Wersja polska i angielska muszą mieć stabilne, indeksowalne URL-e; język nie może zależeć wyłącznie od cookie ani `Accept-Language`.
- [ ] Każda indeksowalna strona PL i EN musi mieć self-canonical do własnej wersji językowej.
- [ ] Strony, które mają odpowiednik w drugim języku, muszą mieć `hreflang` dla `pl`, `en` i sensowny `x-default`.
- [ ] CDN/cache nie może mieszać wersji językowych pod tym samym URL-em.
- [ ] Rate limit nie może blokować poprawnie zweryfikowanych crawlerów wyszukiwarek na publicznych stronach.
- [ ] Publiczne strony rankingów, profili, languages, packages i badge nie mogą dostać przypadkowego `noindex`.
- [ ] Redirecty językowe muszą być stabilne i nie mogą canonicalizować EN do PL ani PL do EN.
- [ ] Zmiany cache muszą być sprawdzane także pod kątem `canonical`, `hreflang`, `robots`, `sitemap.xml` i statusów HTTP.

## Milestone 1 - Zamknąć największe ryzyka ruchu publicznego

Cel: anonimowy ruch publiczny ma być obsługiwany głównie przez cache lub tanią ścieżkę aplikacji, a nie przez pełne renderowanie w Racku.

Ryzyka:

- `Set-Cookie` dla locale oraz `Vary: Cookie` mogą uniemożliwić efektywny cache współdzielony.
- Same nagłówki `Cache-Control` nie chronią aplikacji, jeśli nie ma realnego cache na proxy/CDN.
- Badge i strony publiczne mogą stać się najtańszym sposobem na zajęcie wszystkich threadów Racka.
- Niepoprawny cache albo redirect językowy może pomieszać wersje PL/EN i pogorszyć indeksowanie.

Taski:

- [x] Przestać ustawiać cookie `locale` na anonimowych requestach, jeśli wartość cookie nie musi się zmienić.
- [x] Rozdzielić publiczne i prywatne nagłówki cache tak, żeby `Vary: Cookie` pojawiało się tylko tam, gdzie odpowiedź rzeczywiście zależy od sesji.
- [x] Dopisać testy Rack dla publicznych stron: brak zbędnego `Set-Cookie`, brak `Vary: Cookie`, poprawny `ETag`, poprawne `304`.
- [x] Dopisać testy Rack dla zalogowanego profilu: prywatny cache, brak publicznego cache dla panelu Discord.
- [x] Dopisać testy SEO dla PL i EN: self-canonical, `hreflang`, brak `noindex`, poprawny język treści i stabilny URL.
- [x] Dodać lub udokumentować konfigurację proxy/CDN z microcache dla publicznego HTML, SVG badge i redirectów publicznych.
- [ ] Skonfigurować cache/CDN tak, żeby rozróżniał warianty po URL, a nie po cookie języka.
- [x] Dodać rate limit na `/auth/*`, `/badges/*`, `/internal/*` i najcięższe publiczne endpointy.
- [x] Dodać zasady rate limitu dla crawlerów: brak blokady indeksowalnych stron przy normalnym crawl rate i osobne limity na kosztowne nadużycia.
- [ ] Zweryfikować produkcyjnie nagłówki dla `/latest`, profilu, badge istniejącego i badge brakującego.
- [ ] Zweryfikować produkcyjnie SEO dla par PL/EN, np. `/latest` i `/en/latest`, wraz z canonical i `hreflang`.
- [ ] Zmierzyć ruch publiczny po zmianach prostym testem `wrk` albo `k6`.

Kryteria akceptacji:

- [x] Anonimowe publiczne strony mogą być cache'owane współdzielnie.
- [x] Zalogowane odpowiedzi nie trafiają do publicznego cache.
- [x] Przy powtarzalnych requestach aplikacja zwraca `304` bez pełnego renderowania.
- [ ] Publiczny spike nie zajmuje łatwo wszystkich threadów Racka.
- [x] Obie wersje językowe pozostają indeksowalne i nie wskazują canonicalem na inny język.

## Milestone 2 - Zabezpieczyć endpointy operacyjne, roboty i sesje

Cel: endpointy operacyjne mogą pozostać publicznie dostępne do ręcznej kontroli, ale nie mogą trafiać do indeksu ani ścieżek crawlerów, a sesja użytkownika ma jawnie ustawione bezpieczne właściwości.

Ryzyka:

- `/internal/jobs` ujawnia stan operacyjny i może obciążać bazę, więc musi być wyłączone z indeksowania i agresywnego crawlowania.
- Sesja polega częściowo na defaultach Racka.
- `POST /logout` nie ma osobnej ochrony przed przypadkowym cross-site wywołaniem.

Taski:

- [x] Zostawić `/internal/jobs` publiczne, ale z `X-Robots-Tag: noindex, nofollow, noarchive` i metatagami `noindex,nofollow`.
- [x] Dodać `/internal/` do `robots.txt` jako `Disallow`, bez blokowania `/healthz`.
- [x] Zostawić `/healthz` publiczne, ale utrzymać je jako tani endpoint bez odczytu bazy.
- [x] Ustawić jawnie `secure`, `httponly` i `same_site` dla cookie sesji.
- [x] Ustawić jawnie bezpieczne atrybuty dla cookie `locale`.
- [x] Upewnić się, że noindex/robots dla `/internal/jobs` nie zmienia `robots` ani cache publicznych stron.
- [x] Dodać CSRF token albo równoważny mechanizm dla `POST /logout`.
- [x] Dopisać testy bezpieczeństwa nagłówków i cookie.
- [ ] Zweryfikować produkcyjnie, że `/internal/jobs` jest dostępne ręcznie, ale ma `noindex`, `nofollow`, `noarchive`, `no-store` i nie występuje w `sitemap.xml`.

Kryteria akceptacji:

- [x] `/internal/jobs` pozostaje publicznie dostępne, ale nie jest indeksowalne i nie jest sugerowane crawlerom.
- [x] Cookie sesji nie może być odczytane przez JS i jest wysyłane tylko po HTTPS w produkcji.
- [x] Logout nie jest podatny na przypadkowe cross-site POST.

## Milestone 3 - Uodpornić akcje użytkownika na wolne API i locki SQLite

Cel: logowanie GitHub, połączenie Discord i akcje powiązane z zapisem mają być idempotentne, mierzalne i odporne na równoległe requesty.

Ryzyka:

- Discord connect wykonuje zapis, join do guilda, synchronizację ról i welcome message w jednym requestcie.
- Wolny Discord/GitHub może zająć thread aplikacji na kilkadziesiąt sekund.
- Retry SQLite łagodzi locki, ale nie rozwiązuje problemu długiej ścieżki użytkownika.

Taski:

- [x] Spisać wszystkie akcje użytkownika, które zapisują do SQLite lub wołają zewnętrzne API.
- [x] Dodać testy konkurencyjne dla GitHub login/register, Discord connection i Discord invite.
- [x] Wydzielić sync Discord ról i welcome message do idempotentnego joba/outboxa po szybkim zapisaniu intencji użytkownika.
- [x] Zapisywać status akcji Discord: `pending`, `synced`, `failed`, `retryable`.
- [x] Pokazywać użytkownikowi bezpieczny komunikat, gdy Discord sync jest w toku albo wymaga ponowienia.
- [x] Skrócić timeouty HTTP dla requestów wykonywanych w ścieżce użytkownika.
- [x] Dodać metrykę/licznik dla retry SQLite, timeoutów GitHub/Discord i błędów synchronizacji.
- [x] Upewnić się, że ponowne kliknięcie tej samej akcji nie tworzy duplikatów i nie psuje stanu.

Kryteria akceptacji:

- [x] Request użytkownika nie czeka na niekrytyczne operacje Discord.
- [x] Równoległe requesty tej samej osoby kończą w tym samym poprawnym stanie.
- [x] Błąd Discord nie psuje logowania GitHub ani publicznego profilu.
- [x] Każdy retryable failure jest widoczny operacyjnie.

## Milestone 4 - Oddzielić publiczny odczyt od procesów zapisujących

Cel: monthly, packages i akcje użytkownika nie powinny blokować publicznych stron w tym samym pliku SQLite.

Ryzyka:

- SQLite ma jednego writera; WAL pomaga, ale nie usuwa limitu.
- Monthly i packages zapisują dużo danych w czasie, kiedy publiczne strony czytają rankingi.
- `latest` musi pozostać na ostatnim w pełni opublikowanym miesiącu aż do zakończenia całego importu kolejnego miesiąca.

Taski:

- [x] Zdefiniować formalnie, co znaczy "opublikowany miesiąc" dla wszystkich stron: users, repositories, organizations, organization repositories, languages, packages i badge.
- [x] Upewnić się, że nowy miesiąc staje się publiczny dopiero po zakończeniu monthly oraz wymaganych danych pochodnych.
- [x] Upewnić się, że `sitemap.xml`, canonicale i `hreflang` wskazują tylko opublikowane miesiące albo stabilny alias `latest`.
- [x] Rozważyć osobny read-only snapshot SQLite dla publicznych stron i osobny plik dla user actions/job state.
- [x] Zaprojektować atomową promocję snapshotu: staging -> verified -> published.
- [x] Dodać rollback publikacji snapshotu bez ruszania danych roboczych.
- [x] Dodać checkpoint WAL i backup po publikacji snapshotu.
- [x] Przetestować równoległy monthly/packages plus publiczne requesty profili, rankingów, languages i packages.

Kryteria akceptacji:

- [x] Publiczny odczyt nie jest blokowany przez długie joby zapisujące.
- [x] Nie da się częściowo opublikować nowego miesiąca.
- [x] Rollback do poprzedniego miesiąca jest prosty i przetestowany.
- [x] Crawlery nie widzą częściowo opublikowanych URL-i dla nowego miesiąca.

## Milestone 5 - Zmierzyć i zoptymalizować najcięższe publiczne ścieżki

Cel: znać realne limity aplikacji i usuwać bottlenecki na podstawie pomiarów, nie intuicji.

Ryzyka:

- Brak load testu oznacza brak wiedzy, kiedy aplikacja zacznie zwalniać.
- Indeksy lub zapytania mogą być dobre lokalnie, ale słabe na produkcyjnej bazie.
- Gzip w Racku zmniejsza transfer, ale kosztuje CPU na jedynym web procesie.

Taski:

- [x] Przygotować scenariusze `k6` albo `wrk`: `/latest`, rankingi szczegółowe, profile, organizations, languages, packages, badge.
- [x] Ustalić minimalne SLO: p95, p99, błędy 5xx, maksymalne użycie CPU/RAM.
- [x] Dla najwolniejszych zapytań zebrać `EXPLAIN QUERY PLAN`.
- [x] Dodać brakujące indeksy tylko tam, gdzie potwierdza to plan zapytania.
- [x] Sprawdzić, czy gzip powinien zostać w Racku, czy przejść do nginx/CDN.
- [x] Dodać krótki negative cache tylko dla bezpiecznych 404, które są często odpytywane, nie zależą od sesji i nie mogą pojawić się po zakończeniu aktualnego monthly/packages.
- [x] Sprawdzić, że testy obciążeniowe nie używają scenariuszy blokujących crawlery przez rate limit.
- [x] Porównać wyniki przed i po zmianach.

Kryteria akceptacji:

- [x] Istnieje powtarzalny test obciążeniowy.
- [x] Znamy bezpieczny poziom ruchu dla obecnego serwera.
- [x] Najwolniejsze publiczne ścieżki mają konkretne pomiary i decyzje.

## Milestone 6 - Obserwowalność i runbook produkcyjny

Cel: problemy mają być wykrywalne zanim użytkownicy zaczną zgłaszać awarie.

Ryzyka:

- Bez metryk retry SQLite może ukrywać narastający problem.
- Brak alertów na joby miesięczne i packages utrudnia reakcję.
- Brak runbooka wydłuża awarię.

Taski:

- [x] Dodać structured logging z request id.
- [x] Logować latency, status, path template i informację cache hit/miss tam, gdzie jest dostępna.
- [x] Mierzyć SQLite lock retries i czas oczekiwania na DB; utrzymać liczniki timeoutów HTTP i błędów API zewnętrznych w istniejących adapterach.
- [x] Dodać alert, gdy monthly/packages nie skończy się w oczekiwanym oknie.
- [x] Dodać alert na wzrost 5xx, p95 latency i liczbę retry SQLite.
- [x] Przygotować runbook: deploy, rollback, restart web, restart Discord bot, naprawa stuck monthly/packages, restore backupu.
- [ ] Sprawdzić restore backupu na kopii bazy.

Kryteria akceptacji:

- [ ] Da się zobaczyć, czy problemem jest DB, zewnętrzne API, CPU, pamięć czy cache.
- [ ] Stuck job miesięczny jest wykrywany automatycznie.
- [ ] Restore backupu jest przećwiczony, nie tylko opisany.

## Milestone 7 - Bezpieczniejszy deploy i plan skalowania

Cel: deploy nie powinien robić niepotrzebnego downtime ani zwiększać ryzyka, gdy monthly/packages działa w tle.

Ryzyka:

- Aktualny deploy restartuje pojedynczą instancję web.
- Jeden kontener web z limitem CPU/RAM ma mały margines na spike.
- Skalowanie poziome bez oddzielenia SQLite read path może zwiększyć liczbę locków zamiast pomóc.

Taski:

- [x] Dodać health check po starcie nowego kontenera przed uznaniem deployu za udany.
- [x] Upewnić się, że deploy nie restartuje ani nie przerywa aktywnego monthly/packages.
- [x] Dodać rollback obrazu albo wersji release.
- [x] Rozważyć systemd socket activation, blue-green albo drugi web worker dopiero po ustabilizowaniu read-only snapshotu.
- [x] Spisać limit obecnej architektury: jeden host, jeden web container, SQLite, cache przed aplikacją.
- [x] Przygotować plan awaryjny na duży publiczny spike: włączenie agresywniejszego CDN cache, tymczasowe rate limity, statyczna strona statusowa.
- [x] Przy planie awaryjnym zachować indeksowalność publicznych stron PL/EN i nie włączać globalnego `noindex`.

Kryteria akceptacji:

- [x] Deploy ma jasny smoke test i rollback.
- [x] Wiadomo, co zrobić przy nagłym wzroście ruchu.
- [x] Skalowanie nie zwiększa ryzyka locków SQLite.

## Milestone 8 - Poprawność danych i historyczne metryki

Cel: po ustabilizowaniu ruchu dopiąć semantykę danych miesięcznych.

Ryzyka:

- Historyczne rankingi mogą mieszać dane z końca miesiąca z danymi pobranymi później.
- Packages korzystają z metryk repozytoriów dla danego okresu, więc błędna semantyka gwiazdek przenosi się dalej.

Taski:

- [x] Przywrócić temat historycznych gwiazdek jako osobny plan implementacyjny.
- [x] Dla GitHuba liczyć `stargazers_count` na koniec miesiąca, a `monthly_stars_delta` po `starred_at` z danego miesiąca.
- [x] Zostawić jawny fallback dla platform bez historycznego API.
- [x] Dopisać testy dla repo userów, repo organizacji i rankingów packages korzystających z tego samego `period_start`.
- [x] Udokumentować, które metryki są historyczne, a które są wartością obserwowaną w czasie crawla.
- [x] Zaplanować backfill tylko po oszacowaniu kosztu API i czasu wykonania.

Kryteria akceptacji:

- [x] Miesięczne gwiazdki GitHuba nie zawierają gwiazdek zdobytych po końcu miesiąca.
- [x] Packages i languages pokazują dane zgodne z opublikowanym miesiącem.
- [x] Dokumentacja jasno mówi, gdzie kończy się precyzja historyczna.

## Milestone 9 - Discord role językowe i kolejność badge'y profilu

Cel: uprościć krajowe role Discorda, dodać role językowe wyliczane z już opublikowanych danych i pokazać je na profilu w kolejności zgodnej z produktem: kraj, język, miasto.

Ryzyka:

- Obecny model ról Discorda jest częściowo zaszyty w statycznych kluczach ENV oraz katalogu miast; dla języków to nie wystarczy, bo nowe języki mogą pojawić się dopiero po crawlu.
- Dzisiejszy profil użytkownika i `BadgePolicy` zakładają w praktyce jeden główny badge użytkownika, więc dodanie badge'a językowego bez jawnej kolejności łatwo zrobi niespójność między profilem, SVG badge i panelem Discord.
- Dociąganie rankingu języków w osobnym etapie crawla zwiększyłoby coupling i koszt publikacji, mimo że potrzebne dane już są w opublikowanych repozytoriach.
- Role typu `Top 100 <język>` i otwarte role `<język>` mają różne zasady wejścia; jeśli nie zostaną nazwane i policzone w jednym miejscu, szybko powstanie rozjazd między profilem, synchronizacją Discorda i welcome message.

Taski:

- [ ] Usunąć rolę `Top 10 PL` z polityki Discorda i welcome message; `Top 100 PL` ma przejąć jej dotychczasowy kolor i być jedyną krajową rolą rankingową.
- [ ] Wydzielić jeden moduł odpowiedzialny za semantykę ról Discorda: kraj, miasto, `Top 100 <język>` i otwarte `<język>`, tak żeby panel profilu, synchronizacja ról i welcome message korzystały z tego samego kontraktu.
- [ ] Policzyć dostęp językowy z już opublikowanych repozytoriów zamiast dodawać nowy krok do crawla.
- [ ] Dla ról `Top 100 <język>` brać tylko użytkowników z repozytoriami w danym języku, które mają co najmniej `5` gwiazdek, i wyliczać pozycję na podstawie tych danych.
- [ ] Dla otwartych ról `<język>` wpuszczać każdego użytkownika, który ma co najmniej jedno repozytorium w tym języku, niezależnie od miejsca w rankingu.
- [ ] Dodać automatyczne wykrywanie nowych języków po publikacji danych i zapewnić utworzenie odpowiadających im ról/kanałów Discord bez ręcznego dopisywania stałych w kodzie.
- [ ] Zastąpić statyczne mapowanie ENV dla ról językowych mechanizmem, który potrafi odczytać lub utworzyć role dynamicznie per język, a nadal zachowuje jawne zarządzanie istniejącymi rolami krajowymi i miejskimi.
- [ ] Pokazać na profilu dostępne grupy językowe w panelu Discord, ale nie dodawać nowych publicznych stron rankingowych ani linków do osobnego rankingu językowych grup Discord.
- [ ] Rozszerzyć `BadgePolicy` i profil użytkownika tak, aby badge'y były listą uporządkowaną jawnie według priorytetu: najpierw kraj, potem najwyższy badge językowy, potem miasto.
- [ ] Utrzymać zgodność publicznego SVG badge użytkownika z nową kolejnością: endpoint badge renderuje pierwszy badge z uporządkowanej listy, bez zmiany kontraktu URL.
- [ ] Dopisać testy kontraktowe dla: usunięcia `Top 10 PL`, kolejności badge'y `country -> language -> city`, dynamicznego pojawienia się nowego języka oraz rozróżnienia między `Top 100 <język>` i otwartym `<język>`.

Kryteria akceptacji:

- [ ] Użytkownik z miejscem w `Top 100 PL` widzi tylko tę krajową rolę, w dotychczasowym kolorze roli `Top 10 PL`.
- [ ] Użytkownik może równocześnie dostać role `Top 100 <język>` i otwarte role `<język>` dla wielu języków bez ręcznego dopisywania tych języków do kodu.
- [ ] Nowy język wykryty po crawlu pojawia się automatycznie w mechanizmie synchronizacji Discorda i na profilu użytkownika.
- [ ] Profil pokazuje badge'y w kolejności: kraj, język, miasto.
- [ ] Publiczny badge SVG użytkownika pozostaje stabilny i wybiera najwyższy badge według tej samej kolejności.

## Definition of Done dla każdego milestone'a

- [ ] Zmiana ma testy na najważniejszy kontrakt publiczny albo operacyjny.
- [ ] Zmiana dotykająca publicznych stron ma smoke test SEO dla PL i EN: status 200, canonical, `hreflang`, robots i brak mieszania języków przez cache.
- [ ] `.githooks/pre-commit` przechodzi bez pomijania hooków.
- [ ] Zmiana jest wdrożona albo ma jasną instrukcję wdrożenia.
- [ ] Po wdrożeniu wykonano smoke test produkcyjny.
- [ ] Ryzyko rollbacku jest opisane przed deployem.
- [ ] Zadanie jest skomitowane.
