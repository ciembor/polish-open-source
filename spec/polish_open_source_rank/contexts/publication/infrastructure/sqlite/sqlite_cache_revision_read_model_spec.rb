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
    seed_run(database, period_start: '2026-05-01', period_end: '2026-06-01', status: 'running', finished_at: nil)
    seed_user_stats(database, period_start: '2026-05-01')

    expect(read_model.latest_period).to eq('2026-04-01')
    expect(read_model.recorded_period?('2026-04-01')).to be(true)
    expect(read_model.recorded_period?('2026-05-01')).to be(false)
    expect(read_model.public_cache_revision('2026-04-01')).to eq('2026-05-01T00:30:00Z')
    expect(read_model.public_cache_revision(nil)).to be_nil
  end

  it 'includes materialized badges in the public cache revision' do
    database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    )
    database.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    read_model = described_class.new(database)

    seed_run(database)
    seed_user(database)
    seed_user_stats(database)
    seed_published_badge(database, updated_at: '2026-05-01T00:45:00Z')

    expect(read_model.public_cache_revision('2026-04-01')).to eq('2026-05-01T00:45:00Z')
  end

  it 'uses explicit public snapshot publications when present' do
    database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    )
    database.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    read_model = described_class.new(database)

    seed_run(database, period_start: '2026-04-01')
    seed_run(database, period_start: '2026-05-01')
    seed_user(database)
    seed_user_stats(database, period_start: '2026-04-01')
    seed_user_stats(database, period_start: '2026-05-01')
    seed_publication(database, '2026-04-01', status: 'superseded')
    seed_publication(database, '2026-05-01')

    expect(read_model.latest_period).to eq('2026-05-01')
    expect(read_model.recorded_period?('2026-04-01')).to be(true)
    expect(read_model.recorded_period?('2026-05-01')).to be(true)
    expect(read_model.recorded_period?('2026-06-01')).to be(false)
  end

  def seed_run(database, period_start: '2026-04-01', period_end: '2026-05-01', status: 'finished',
               finished_at: '2026-05-01T00:30:00Z')
    database.execute(
      'INSERT INTO sync_runs(period_start, period_end, status, started_at, finished_at) VALUES (?, ?, ?, ?, ?)',
      [period_start, period_end, status, '2026-05-01T00:00:00Z', finished_at]
    )
  end

  def seed_user(database)
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 1, 'alice', 'https://github.com/alice', '2026-05-01T00:01:00Z']
    )
  end

  def seed_user_stats(database, period_start: '2026-04-01')
    insert_stats_sql = <<~SQL
      INSERT INTO user_monthly_stats(
        period_start, platform, user_github_id, login, city, country, public_repo_count,
        total_stars, monthly_stars_delta, merged_pull_requests_count, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
    database.execute(
      insert_stats_sql,
      [
        period_start, 'github', 1, 'alice', 'Kraków', 'Poland', 1, 10, 2, 3,
        '2026-05-01T00:10:00Z'
      ]
    )
  end

  def seed_publication(database, period_start, status: 'published')
    database.execute(
      <<~SQL,
        INSERT INTO public_snapshot_publications(period_start, status, created_at, updated_at)
        VALUES (?, ?, ?, ?)
      SQL
      [period_start, status, '2026-06-01T00:00:00Z', '2026-06-01T00:00:00Z']
    )
  end

  def seed_published_badge(database, updated_at:)
    database.execute(
      <<~SQL,
        INSERT INTO published_badges(
          period_start, badge_kind, platform, subject_github_id, label, status, rank, created_at, updated_at
        )
        VALUES ('2026-04-01', 'user', 'github', 1, 'Polish Open Source', 'ranked', 1, ?, ?)
      SQL
      [updated_at, updated_at]
    )
  end
end
