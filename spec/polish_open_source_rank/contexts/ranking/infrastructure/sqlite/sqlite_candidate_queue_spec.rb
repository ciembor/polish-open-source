# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteCandidateQueue do
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:clock) { -> { Time.utc(2026, 5, 1, 12, 0, 0) } }
  let(:queue) { described_class.new(database, clock: clock) }

  it 'records, merges, filters, and marks candidate users' do
    queue.record(period, github_id: 1, login: 'alice', source_query: 'Poland')
    queue.record(period, source_id: 2, login: 'bob', source_query: 'Poland', platform: 'gitlab')
    queue.record(period, github_id: 1, login: 'alice', source_query: 'Krakow')

    expect(queue.pending(period)).to contain_exactly(
      include(login: 'alice', source_id: 1),
      include(login: 'bob', source_id: 2)
    )
    expect(queue.pending(period, platform: 'gitlab')).to contain_exactly(include(login: 'bob'))

    queue.mark(period, 'alice', 'failed', 'temporary')
    queue.mark(period, 'gitlab', 'bob', 'processed')

    expect(candidate('alice')).to include(
      platform: 'github',
      source_query: 'Poland, Krakow',
      status: 'failed',
      error: 'temporary',
      updated_at: '2026-05-01T12:00:00Z'
    )
    expect(queue.pending(period)).to be_empty
  end

  it 'reports a user as processed only after required snapshot records exist' do
    seed_user
    seed_user_stats(public_repo_count: 1)

    expect(queue.processed_user?(period, 'github', 1)).to be_nil

    seed_repository
    seed_repository_stats

    expect(queue.processed_user?(period, 'github', 1)).to eq(1)
    expect(queue.processed_user?(period, 1)).to eq(1)
  end

  def candidate(login)
    database.fetch_all('SELECT * FROM candidate_users WHERE login = ?', [login]).first
  end

  def seed_user
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 1, 'alice', 'https://github.com/alice', '2026-05-01T00:01:00Z']
    )
  end

  def seed_user_stats(public_repo_count:)
    database.execute(user_stats_sql, [period.start_date.to_s, 'github', 1, 'alice', 'Kraków', 'Poland',
                                      public_repo_count, 10, 1, 1, '2026-05-01T00:10:00Z'])
  end

  def seed_repository
    database.execute(
      repository_sql,
      ['github', 10, 1, 'alice', 'app', 'alice/app', 'https://github.com/alice/app', 0, 0,
       '2026-05-01T00:01:00Z']
    )
  end

  def seed_repository_stats
    database.execute(repository_stats_sql, [period.start_date.to_s, 'github', 10, 1, 'alice', 'Kraków', 'Poland',
                                            10, 1, '2026-05-01T00:10:00Z'])
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
