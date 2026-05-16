# Backlog

## Done

- [x] Ustalić nowy kierunek projektu bez opierania się na historycznych plikach `README.md` i `locations/`.
- [x] Dodać lokalny, ignorowany plik `.env.local` na token GitHuba oraz przykład konfiguracji bez sekretów.
- [x] Zbudować szkielet aplikacji Ruby z Bundlerem, CLI, WWW i katalogami pod domenę, aplikację oraz infrastrukturę.
- [x] Zaimplementować stałe lokalizacji dla Polski i wspieranych miast oraz klasyfikację profili GitHuba.
- [x] Przygotować schemat SQLite i zapis miesięcznych snapshotów użytkowników, repozytoriów oraz kandydatów do synchronizacji.
- [x] Dodać adapter GitHub API z odstępami między requestami, obsługą limitów, retry, backoffem i checkpointami joba.
- [x] Dodać miesięczny job pobierania danych i idempotentne wznawianie.
- [x] Dodać rankingi Polski i miast: top użytkownicy, trending użytkownicy, aktywni użytkownicy, top repozytoria i trending repozytoria.
- [x] Zbudować semantyczne widoki HTML5 z dobrym SEO.
- [x] Dodać RSpec, SimpleCov z wymaganym 100% coverage, RuboCop, Reek i pre-commit.
- [x] Uruchomić pełną jakość lokalnie i uzupełnić dokumentację uruchomienia.
- [x] Dodać obsługę działania pod `/polish-github-rank`.
- [x] Dodać Podman/systemd/Nginx artefakty deployu i GitHub Actions workflow.
- [x] Przygotować serwer: katalog aplikacji, `.env.local`, Nginx proxy, systemd service i miesięczny timer.
- [x] Wdrożyć aplikację na `https://maciej-ciemborowicz.eu/polish-github-rank` i zweryfikować `/healthz`.
- [x] Przygotować osobny klucz SSH dla GitHub Actions i dodać jego publiczną część do `authorized_keys`.

## Blocked

- [ ] Ustawić sekret repozytorium `DEPLOY_KEY`; lokalne `gh auth` ma nieważny token, więc nie mogę zrobić tego automatycznie z tej sesji.
- [ ] Po ustawieniu sekretu wypchnąć aktualny HEAD na `master`, żeby workflow przejął kolejne deploye.
