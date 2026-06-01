# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteContributorAccessReadModel do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:read_model) { described_class.new(database) }

  it 'returns Discord access role keys from country, city, and language ranks' do
    seed_user(id: 1, login: 'alice', city: 'Kraków', total_stars: 100)
    seed_user(id: 2, login: 'bob', city: 'Kraków', total_stars: 90)
    seed_user(id: 3, login: 'carol', city: 'Wrocław', total_stars: 80)
    seed_repository(id: 10, owner: { id: 1, login: 'alice' }, language: 'Ruby', stars: 30)
    seed_repository(id: 11, owner: { id: 1, login: 'alice' }, language: 'JavaScript', stars: 3)
    seed_repository(id: 12, owner: { id: 2, login: 'bob' }, language: 'Ruby', stars: 20)

    expect(read_model.access('github', 1, period_start: period)).to include(
      country_rank: 1,
      city: 'Kraków',
      city_slug: 'krakow',
      city_rank: 1,
      language_accesses: contain_exactly(
        include(language: 'Ruby', member: true, rank: 1),
        include(language: 'JavaScript', member: true, rank: nil)
      ),
      role_keys: contain_exactly(
        'DISCORD_ROLE_TOP_100_PL',
        'DISCORD_ROLE_TOP_100_CITY_KRAKOW',
        'DISCORD_ROLE_LANGUAGE:ruby:Ruby',
        'DISCORD_ROLE_TOP_100_LANGUAGE:ruby:Ruby',
        'DISCORD_ROLE_LANGUAGE:javascript:JavaScript',
        'DISCORD_ROLE_BADGE_TOP_1'
      )
    )
    expect(read_model.access('github', 2, period_start: period).fetch(:badge_role_key)).to eq(
      'DISCORD_ROLE_BADGE_TOP_2'
    )
    expect(read_model.access('github', 3, period_start: period).fetch(:badge_role_key)).to eq(
      'DISCORD_ROLE_BADGE_TOP_3'
    )
  end

  it 'returns empty access when no public period exists' do
    expect(read_model.access('github', 1, period_start: nil)).to eq(
      country_rank: nil,
      city: nil,
      city_slug: nil,
      city_rank: nil,
      language_accesses: [],
      role_keys: [],
      access_role_keys: [],
      badge_role_key: nil
    )
  end

  it 'uses the latest finished ranking when no period is provided' do
    seed_run('2026-04-01')
    seed_run('2026-05-01', status: 'running')
    seed_user(id: 1, login: 'alice', city: 'Kraków', total_stars: 100, period_start: '2026-04-01')
    seed_user(id: 2, login: 'bob', city: 'Kraków', total_stars: 200, period_start: '2026-05-01')

    expect(read_model.access('github', 1, period_start: nil)).to include(country_rank: 1)
    expect(read_model.access('github', 2, period_start: nil)).to include(country_rank: nil)
  end

  it 'lists published languages for the effective public period' do
    seed_run(period)
    seed_user(id: 1, login: 'alice', city: 'Kraków', total_stars: 100)
    seed_repository(id: 10, owner: { id: 1, login: 'alice' }, language: 'Ruby', stars: 30)

    expect(read_model.published_languages(period_start: period)).to eq(['Ruby'])
    expect(read_model.published_languages(period_start: nil)).to eq(['Ruby'])
  end

  it 'returns no published languages without a public period' do
    expect(read_model.published_languages(period_start: nil)).to eq([])
  end

  def period
    '2026-04-01'
  end

  def seed_run(period_start, status: 'finished')
    database.execute(
      'INSERT INTO sync_runs(period_start, period_end, status, started_at) VALUES (?, ?, ?, ?)',
      [period_start, '2026-05-01', status, '2026-05-01T00:00:00Z']
    )
  end

  def seed_user(id:, login:, city:, total_stars:, period_start: period)
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', id, login, "https://github.com/#{login}", '2026-05-01T00:01:00Z']
    )
    database.execute(user_stats_sql, [period_start, 'github', id, login, city, 'Poland', 1, total_stars, 0, 1,
                                      '2026-05-01T00:10:00Z'])
  end

  def seed_repository(id:, owner:, language:, stars:, period_start: period)
    database.execute(
      <<~SQL,
        INSERT INTO repositories(
          platform, github_id, owner_github_id, owner_login, name, full_name, html_url, language, fork, archived,
          updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?)
      SQL
      ['github', id, owner.fetch(:id), owner.fetch(:login), "repo-#{id}", "#{owner.fetch(:login)}/repo-#{id}",
       "https://github.com/#{owner.fetch(:login)}/repo-#{id}",
       language, '2026-05-01T00:01:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO repository_monthly_stats(
          period_start, platform, repository_github_id, owner_github_id, owner_login, owner_city,
          owner_country, stargazers_count, monthly_stars_delta, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [period_start, 'github', id, owner.fetch(:id), owner.fetch(:login), 'Kraków', 'Poland', stars, 0,
       '2026-05-01T00:10:00Z']
    )
  end

  def user_stats_sql
    <<~SQL
      INSERT INTO user_monthly_stats(
        period_start, platform, user_github_id, login, city, country, public_repo_count,
        total_stars, monthly_stars_delta, merged_pull_requests_count, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end
end
