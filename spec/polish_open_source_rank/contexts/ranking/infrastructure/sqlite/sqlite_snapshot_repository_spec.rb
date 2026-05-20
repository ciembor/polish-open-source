# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRepository do
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }
  let(:previous_period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-03') }
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:clock) { -> { Time.utc(2026, 5, 1, 12, 0, 0) } }
  let(:repository) { described_class.new(database, clock: clock) }

  it 'persists users, repositories, monthly stats, and star observations' do
    repository.upsert_user(user_attributes)
    repository.record_user_stats(user_stats)
    repository.upsert_repository(repository_attributes)
    repository.record_repository_stats(repository_stats(period: previous_period, stars: 27, delta: 2))
    repository.record_repository_stats(repository_stats(period: period, stars: 30, delta: 3))

    expect(row('users')).to include(
      platform: 'github',
      login: 'alice',
      email: 'alice@example.com',
      updated_at: '2026-05-01T12:00:00Z'
    )
    expect(row('repositories')).to include(platform: 'github', full_name: 'alice/app', fork: 0, archived: 1)
    expect(row('user_monthly_stats')).to include(total_stars: 30, monthly_stars_delta: 4)
    expect(row('repository_monthly_stats')).to include(stargazers_count: 27, monthly_stars_delta: 2)
    expect(repository.previous_repository_stargazers_count(period, 'github', 100)).to eq(27)
  end

  it 'updates snapshot records through stable platform-qualified identities' do
    repository.upsert_user(user_attributes(login: 'alice'))
    repository.upsert_user(user_attributes(login: 'alice-renamed'))
    repository.upsert_repository(repository_attributes(full_name: 'alice/app'))
    repository.upsert_repository(repository_attributes(full_name: 'alice/new-app'))
    repository.record_user_stats(user_stats(total_stars: 30))
    repository.record_user_stats(user_stats(total_stars: 31))
    repository.record_repository_stats(repository_stats(period: period, stars: 30, delta: 3))
    repository.record_repository_stats(repository_stats(period: period, stars: 31, delta: 4))

    expect(row('users')).to include(login: 'alice-renamed')
    expect(row('repositories')).to include(full_name: 'alice/new-app')
    expect(row('user_monthly_stats')).to include(total_stars: 31)
    expect(row('repository_monthly_stats')).to include(stargazers_count: 31, monthly_stars_delta: 4)
  end

  def row(table)
    database.fetch_all("SELECT * FROM #{table}").first
  end

  def user_attributes(login: 'alice')
    {
      platform: 'github',
      github_id: 10,
      login: login,
      name: 'Alice',
      location_raw: 'Kraków, Poland',
      city: 'Kraków',
      country: 'Poland',
      email: 'alice@example.com',
      homepage: 'https://alice.example.com',
      html_url: 'https://github.com/alice',
      avatar_url: 'https://avatars.example.com/alice.png'
    }
  end

  def user_stats(total_stars: 30)
    {
      period_start: period.start_date.to_s,
      platform: 'github',
      user_github_id: 10,
      login: 'alice',
      city: 'Kraków',
      country: 'Poland',
      public_repo_count: 1,
      total_stars: total_stars,
      monthly_stars_delta: 4,
      public_activity_count: 9
    }
  end

  def repository_attributes(full_name: 'alice/app')
    {
      platform: 'github',
      github_id: 100,
      owner_github_id: 10,
      owner_login: 'alice',
      name: full_name.split('/').last,
      full_name: full_name,
      description: 'App',
      html_url: "https://github.com/#{full_name}",
      homepage: nil,
      language: 'Ruby',
      fork: false,
      archived: true
    }
  end

  def repository_stats(period:, stars:, delta:)
    {
      period_start: period.start_date.to_s,
      platform: 'github',
      repository_github_id: 100,
      owner_github_id: 10,
      owner_login: 'alice',
      owner_city: 'Kraków',
      owner_country: 'Poland',
      stargazers_count: stars,
      monthly_stars_delta: delta
    }
  end
end
