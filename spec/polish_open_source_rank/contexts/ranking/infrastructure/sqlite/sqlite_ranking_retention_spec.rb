# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingRetention do
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:retention) { described_class.new(database, catalog: catalog) }
  let(:catalog) { PolishOpenSourceRank::Contexts::Ranking::Domain::LocationCatalog }

  it 'keeps only top-100 rows and deletes orphaned users and repositories' do
    101.times do |index|
      id = index + 1
      login = format('user%03d', id)
      repo_id = id + 1000
      seed_user(id, login, 'Kraków')
      seed_user_stats(id, login, 'Kraków', total_stars: id, delta: id, activity: id)
      seed_repository(repo_id, id, login, "#{login}/app")
      seed_repository_stats(repo_id, id, login, 'Kraków', stars: id, delta: id)
    end

    retention.prune(period)

    expect(database.fetch_value('SELECT COUNT(*) FROM user_monthly_stats')).to eq(100)
    expect(database.fetch_value('SELECT COUNT(*) FROM repository_monthly_stats')).to eq(100)
    expect(database.fetch_value('SELECT 1 FROM users WHERE github_id = ?', [1])).to be_nil
    expect(database.fetch_value('SELECT 1 FROM repositories WHERE github_id = ?', [1001])).to be_nil
  end

  it 'binds scope values safely while pruning city rankings' do
    safe_catalog = Module.new
    safe_catalog.const_set(:COUNTRY, 'Poland')
    safe_catalog.const_set(:CITIES, [{ name: "O'City", slug: 'ocity' }].freeze)
    retention = described_class.new(database, catalog: safe_catalog)

    seed_user(1, 'alice', "O'City")
    seed_user_stats(1, 'alice', "O'City", total_stars: 10, delta: 1, activity: 1)
    seed_repository(1001, 1, 'alice', 'alice/app')
    seed_repository_stats(1001, 1, 'alice', "O'City", stars: 10, delta: 1)

    expect { retention.prune(period) }.not_to raise_error
    expect(database.fetch_value('SELECT COUNT(*) FROM user_monthly_stats')).to eq(1)
    expect(database.fetch_value('SELECT COUNT(*) FROM repository_monthly_stats')).to eq(1)
  end

  def seed_user(id, login, _city)
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', id, login, "https://github.com/#{login}", '2026-05-01T00:01:00Z']
    )
  end

  def seed_user_stats(id, login, city, total_stars:, delta:, activity:)
    database.execute(
      user_stats_sql,
      [
        period.start_date.to_s, 'github', id, login, city, 'Poland', 1, total_stars, delta, activity,
        '2026-05-01T00:10:00Z'
      ]
    )
  end

  def seed_repository(id, owner_id, owner_login, full_name)
    database.execute(
      repository_sql,
      [
        'github', id, owner_id, owner_login, full_name.split('/').last, full_name,
        "https://github.com/#{full_name}", 0, 0, '2026-05-01T00:01:00Z'
      ]
    )
  end

  def seed_repository_stats(id, owner_id, owner_login, city, stars:, delta:)
    database.execute(
      repository_stats_sql,
      [
        period.start_date.to_s, 'github', id, owner_id, owner_login, city, 'Poland', stars, delta,
        '2026-05-01T00:10:00Z'
      ]
    )
  end

  def user_stats_sql
    <<~SQL
      INSERT INTO user_monthly_stats(
        period_start, platform, user_github_id, login, city, country, public_repo_count,
        total_stars, monthly_stars_delta, public_activity_count, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end

  def repository_sql
    <<~SQL
      INSERT INTO repositories(
        platform, github_id, owner_github_id, owner_login, name, full_name, html_url, fork, archived, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end

  def repository_stats_sql
    <<~SQL
      INSERT INTO repository_monthly_stats(
        period_start, platform, repository_github_id, owner_github_id, owner_login, owner_city,
        owner_country, stargazers_count, monthly_stars_delta, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end
end
