# Plan dla agenta: historyczne gwiazdki dla miesięcznych rankingów

## Cel

Zmienić semantykę miesięcznych rankingów tak, żeby dla GitHuba wartości gwiazdek były historyczne dla konkretnego miesiąca, a nie aktualne z momentu crawl joba.

Docelowo:

```text
period_start = 2026-04-01
stargazers_count = liczba gwiazdek repo na koniec kwietnia
monthly_stars_delta = liczba gwiazdek zdobytych w kwietniu
observed_at = moment faktycznego pobrania danych
```

## Problem

Obecnie `repository.fetch(:stars)` pochodzi z aktualnego GitHub API `/users/:login/repos` albo `/orgs/:login/repos`.

Jeśli crawl dla kwietnia trwa od 1 maja do 3 czerwca, część rekordów zapisze do `period_start = 2026-04-01`, ale z wartościami gwiazdek z czerwca.

`monthly_stars_delta` bywa liczony z różnicy względem poprzedniego snapshotu, więc też może obejmować gwiazdki zdobyte po miesiącu docelowym.

## Zakres

Zmiana dotyczy przede wszystkim:

```text
lib/polish_open_source_rank/infrastructure/github/gateway.rb
lib/polish_open_source_rank/contexts/ranking/application/run_monthly_snapshot.rb
lib/polish_open_source_rank/contexts/ranking/application/monthly_snapshot_factory.rb
lib/polish_open_source_rank/contexts/ranking/domain/source_repository.rb
```

oraz testów dla:

```text
spec/polish_open_source_rank/infrastructure/github/gateway_spec.rb
spec/polish_open_source_rank/contexts/ranking/application/run_monthly_snapshot_spec.rb
spec/polish_open_source_rank/contexts/ranking/infrastructure/sqlite/sqlite_snapshot_repository_spec.rb
```

Nazwy plików mogą się minimalnie różnić, agent ma sprawdzić aktualne repo.

## Krok 1 - znaleźć aktualny przepływ danych

Prześledzić:

1. `GitHubGateway#repository`
2. `GitHubGateway#each_repository_for`
3. `RunMonthlySnapshot#store_repository`
4. `RunMonthlySnapshot#store_organization_repository`
5. `MonthlySnapshotFactory#repository_snapshot`
6. `MonthlySnapshotFactory#organization_repository_snapshot`
7. zapis do `repository_monthly_stats`
8. zapis do `organization_repository_monthly_stats`

Potwierdzić, gdzie `stars` z `SourceRepository` trafia do `stargazers_count`.

## Krok 2 - dodać obliczanie historycznych gwiazdek

W `GitHubGateway` dodać metodę, np.:

```ruby
def repository_star_snapshot(repository, period)
  owner, repo = repository_coordinates(repository)

  stars_at_period_end = 0
  stars_in_period = 0

  last_page = last_page_number(stargazers_page(owner, repo, 1).headers.fetch('link', nil)) || 1

  last_page.downto(1) do |page|
    stars = stargazers_page(owner, repo, page).body
    times = stars.map { |star| Time.parse(star.fetch('starred_at')) }

    stars_at_period_end += times.count { |time| time.to_date <= period.end_date }
    stars_in_period += times.count { |time| period.cover_time?(time) }

    break if times.any? && times.all? { |time| time.to_date < period.start_date }
  end

  {
    stargazers_count: stars_at_period_end,
    monthly_stars_delta: stars_in_period
  }
end
```

Uwaga: trzeba sprawdzić, czy `period` ma `end_date`. Jeśli nie ma, dodać helper albo użyć końca miesiąca z `start_date`.

Ważne: obecny `repository_stars_delta` już używa:

```ruby
application/vnd.github.star+json
```

i `starred_at`, więc można wykorzystać istniejące metody `stargazers_page`, `count_stars_backwards`, `count_stars`.

## Krok 3 - unikać zliczania tylko gwiazdek z miesiąca

Do `stargazers_count` potrzebne jest count `starred_at <= period.end_date`, nie tylko gwiazdki z miesiąca.

Przykład:

Dla `2026-04`:

```text
stargazers_count = wszystkie gwiazdki do 2026-04-30 23:59:59
monthly_stars_delta = gwiazdki od 2026-04-01 00:00:00 do 2026-04-30 23:59:59
```

## Krok 4 - zmienić RunMonthlySnapshot

Obecnie:

```ruby
monthly_stars_delta = repository_delta(source, repository, period)
metrics.add(repository, monthly_stars_delta)
store.record_repository_snapshot(...)
```

Zastąpić to czymś w tym stylu:

```ruby
stars = repository_star_snapshot(source, repository, period)

historical_repository = repository.with(
  stars: stars.fetch(:stargazers_count)
)

metrics.add(historical_repository, stars.fetch(:monthly_stars_delta))

store.record_repository_snapshot(
  snapshot_factory.repository_snapshot(
    period,
    source,
    profile,
    location,
    historical_repository,
    stars.fetch(:monthly_stars_delta)
  )
)
```

Jeśli `SourceRepository` nie ma `.with`, zrobić prosty konstruktor/helper, np.:

```ruby
repository.merge(stars: stars.fetch(:stargazers_count))
```

zależnie od tego, czym jest `SourceRepository`.

Analogicznie zmienić:

```ruby
store_organization_repository
```

## Krok 5 - fallback dla źródeł bez historycznego API

Nie zakładać, że GitLab/Codeberg obsługują historyczne gwiazdki.

W `RunMonthlySnapshot` dodać helper:

```ruby
def repository_star_snapshot(source, repository, period)
  if source.respond_to?(:repository_star_snapshot)
    source.repository_star_snapshot(repository, period)
  else
    {
      stargazers_count: repository.fetch(:stars),
      monthly_stars_delta: repository_delta(source, repository, period)
    }
  end
end
```

Dla organizacji może używać tej samej metody, bo to nadal repozytorium.

## Krok 6 - usunąć zależność delty od poprzedniego snapshotu dla GitHuba

Dla GitHuba `monthly_stars_delta` powinno być liczone po `starred_at`, nie przez:

```ruby
current_stars - previous_stars
```

Ten fallback może zostać dla GitLaba/Codeberga, ale GitHub powinien używać nowej metody `repository_star_snapshot`.

## Krok 7 - testy jednostkowe GitHubGateway

Dodać testy dla:

1. repo ma gwiazdki przed miesiącem, w miesiącu i po miesiącu
2. `stargazers_count` liczy tylko do końca miesiąca
3. `monthly_stars_delta` liczy tylko gwiazdki w miesiącu
4. gwiazdki po miesiącu nie są doliczane
5. paginacja działa dla wielu stron
6. repo bez gwiazdek zwraca 0/0
7. 403/451 zachowują dotychczasowy bezpieczny fallback, np. 0/0

Przykład oczekiwanej semantyki:

```text
period = 2026-04

starred_at:
2026-03-10
2026-04-02
2026-04-30
2026-05-01

expected:
stargazers_count = 3
monthly_stars_delta = 2
```

## Krok 8 - testy RunMonthlySnapshot

Dodać test, że jeśli source implementuje `repository_star_snapshot`, to:

- zapisany `stargazers_count` pochodzi z `repository_star_snapshot[:stargazers_count]`
- zapisany `monthly_stars_delta` pochodzi z `repository_star_snapshot[:monthly_stars_delta]`
- nie używa aktualnego `repository[:stars]` jako finalnej wartości

Analogicznie dla repo organizacji.

## Krok 9 - testy regresji dla packages

Sprawdzić, czy package ranking nadal joinuje po:

```sql
user_stats.period_start = snapshots.period_start
organization_stats.period_start = snapshots.period_start
```

Jeśli tak, packages automatycznie dostaną historyczne repo stars, o ile miesięczne repo stats są historyczne.

Nie trzeba zmieniać registry downloads, bo API pakietów zwykle nie daje historycznego stanu.

## Krok 10 - migracja danych

Nie trzeba migracji schematu, jeśli zostają te same kolumny:

```text
stargazers_count
monthly_stars_delta
observed_at
```

Ale warto dopisać w dokumentacji semantykę:

```text
For GitHub repositories, stargazers_count is historical at period end.
For non-GitHub platforms, stargazers_count may be observed current value unless platform supports historical stars.
```

## Krok 11 - CLI / opcje

Nie robić flagi, jeśli ma to być domyślne zachowanie.

Jeśli agent chce zachować kompatybilność, może dodać flagę typu:

```bash
--current-stars
```

ale preferowane: historyczne GitHub stars jako default.

## Krok 12 - walidacja lokalna

Uruchomić:

```bash
bundle exec rspec
```

oraz ręcznie, na małym scope/limicie:

```bash
bundle exec ruby bin/monthly_rankings --period 2026-04 --limit 10 --recalculate-stars
```

Jeśli `--recalculate-stars` nie istnieje, sprawdzić faktyczne CLI i uruchomić dostępny odpowiednik.

## Krok 13 - sprawdzenie w SQLite

Po crawlu sprawdzić:

```sql
select full_name, stargazers_count, monthly_stars_delta, observed_at
from repository_monthly_stats
join repositories
  on repositories.github_id = repository_monthly_stats.repository_github_id
where period_start = '2026-04-01'
order by stargazers_count desc
limit 20;
```

Dla repo znanego z gwiazdkami po kwietniu sprawdzić, że `stargazers_count` nie zawiera gwiazdek z maja/czerwca.

## Kryteria akceptacji

1. GitHub `stargazers_count` dla repozytorium w okresie `YYYY-MM` oznacza liczbę gwiazdek na koniec tego miesiąca.
2. GitHub `monthly_stars_delta` oznacza liczbę gwiazdek zdobytych w tym miesiącu.
3. Gwiazdki zdobyte po końcu miesiąca nie wpływają na snapshot wcześniejszego miesiąca.
4. User `total_stars` i organization `total_stars` są sumą historycznych gwiazdek repozytoriów z tego miesiąca.
5. Package ranking korzysta z repo stars dla tego samego `period_start`.
6. Testy przechodzą.
7. W dokumentacji jest jasno opisane, które metryki są historyczne, a które są observed current.
