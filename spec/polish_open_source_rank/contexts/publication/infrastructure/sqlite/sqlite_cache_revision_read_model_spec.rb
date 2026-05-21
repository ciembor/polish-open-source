# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Infrastructure::SQLite::SQLiteCacheRevisionReadModel do
  it 'reports the latest public period and the revision that invalidates public caches' do
    database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    )
    database.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    read_model = described_class.new(database)

    seed_run(database)
    seed_user(database)
    seed_user_stats(database)

    expect(read_model.latest_period).to eq('2026-04-01')
    expect(read_model.recorded_period?('2026-04-01')).to be(true)
    expect(read_model.recorded_period?('2026-05-01')).to be(false)
    expect(read_model.public_cache_revision('2026-04-01')).to eq('2026-05-01T00:30:00Z')
    expect(read_model.public_cache_revision(nil)).to be_nil
  end

  def seed_run(database)
    database.execute(
      'INSERT INTO sync_runs(period_start, period_end, status, started_at, finished_at) VALUES (?, ?, ?, ?, ?)',
      ['2026-04-01', '2026-05-01', 'finished', '2026-05-01T00:00:00Z', '2026-05-01T00:30:00Z']
    )
  end

  def seed_user(database)
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 1, 'alice', 'https://github.com/alice', '2026-05-01T00:01:00Z']
    )
  end

  def seed_user_stats(database)
    insert_stats_sql = <<~SQL
      INSERT INTO user_monthly_stats(
        period_start, platform, user_github_id, login, city, country, public_repo_count,
        total_stars, monthly_stars_delta, public_activity_count, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
    database.execute(
      insert_stats_sql,
      [
        '2026-04-01', 'github', 1, 'alice', 'Kraków', 'Poland', 1, 10, 2, 3,
        '2026-05-01T00:10:00Z'
      ]
    )
  end
end
