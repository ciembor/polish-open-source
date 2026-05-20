# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Infrastructure::SQLite::SQLiteProfileReadModel do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:read_model) { described_class.new(database) }

  it 'returns user profiles with ranking badges and top repositories' do
    seed_user(id: 1, login: 'alice', total_stars: 100)
    seed_user(id: 2, login: 'bob', total_stars: 90)
    seed_repository(id: 10, owner_id: 1, owner: 'alice', full_name: 'alice/app', stars: 30)

    profile = read_model.user_profile('github', 'alice', period_start: period)

    expect(profile).to include(login: 'alice', elite_rank: 1)
    expect(profile.fetch(:elite_badge)).to include(value: '1st', status: 'ranked')
    expect(profile.fetch(:repositories)).to contain_exactly(include(full_name: 'alice/app', stargazers_count: 30))
  end

  it 'returns historical and contender user badges' do
    seed_user(id: 1, login: 'alumni', total_stars: 1_000, period_start: '2026-03-01')
    11.times do |index|
      seed_user(id: index + 2, login: "user#{index}", total_stars: 100 - index)
    end
    seed_user(id: 20, login: 'contender', total_stars: 1)

    expect(read_model.user_profile('github', 'alumni', period_start: period).fetch(:elite_badge)).to include(
      value: 'alumni',
      status: 'alumni'
    )
    expect(read_model.user_profile('github', 'contender', period_start: period).fetch(:elite_badge)).to include(
      value: 'contender',
      status: 'contender'
    )
  end

  it 'returns repository profiles with top-100 badges' do
    seed_user(id: 1, login: 'alice', total_stars: 100)
    seed_repository(id: 10, owner_id: 1, owner: 'alice', full_name: 'alice/app', stars: 30)

    profile = read_model.repository_profile('github', 'alice', 'app', period_start: period)

    expect(profile).to include(full_name: 'alice/app', elite_rank: 1)
    expect(profile.fetch(:polish_repo_badge)).to include(value: '1st', status: 'ranked')
  end

  it 'returns empty ranking details for records without a public period' do
    seed_user_record(id: 1, login: 'alice')
    seed_repository_record(id: 10, owner_id: 1, owner: 'alice', full_name: 'alice/app')

    user = read_model.user_profile('github', 'alice', period_start: nil)
    repository = read_model.repository_profile('github', 'alice', 'app', period_start: nil)

    expect(user).to include(elite_rank: nil, repositories: [])
    expect(repository).to include(elite_rank: nil)
    expect(read_model.user_profile('github', 'missing', period_start: period)).to be_nil
    expect(read_model.repository_profile('github', 'alice', 'missing', period_start: period)).to be_nil
  end

  def period
    '2026-04-01'
  end

  def seed_user(id:, login:, total_stars:, period_start: period)
    seed_user_record(id: id, login: login)
    database.execute(user_stats_sql, [period_start, 'github', id, login, 'Kraków', 'Poland', 1, total_stars, 0, 1,
                                      '2026-05-01T00:10:00Z'])
  end

  def seed_user_record(id:, login:)
    database.execute(
      'INSERT OR IGNORE INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', id, login, "https://github.com/#{login}", '2026-05-01T00:01:00Z']
    )
  end

  def seed_repository(id:, owner_id:, owner:, full_name:, stars:)
    seed_repository_record(id: id, owner_id: owner_id, owner: owner, full_name: full_name)
    database.execute(repository_stats_sql, [period, 'github', id, owner_id, owner, 'Kraków', 'Poland', stars, 0,
                                            '2026-05-01T00:10:00Z'])
  end

  def seed_repository_record(id:, owner_id:, owner:, full_name:)
    database.execute(
      repository_sql,
      ['github', id, owner_id, owner, full_name.split('/').last, full_name, 'https://github.com/alice/app',
       '2026-05-01T00:01:00Z']
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
      VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?)
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
