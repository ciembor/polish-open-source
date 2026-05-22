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
    expect(profile.fetch(:profile_badge)).to include(label: 'Polish Open Source', value: '1st', status: 'ranked')
    expect(profile.fetch(:repositories)).to contain_exactly(
      include(full_name: 'alice/app', stargazers_count: 30, polish_repo_badge: include(value: '1st'))
    )
  end

  it 'returns city badges when the user is outside the Poland ranking' do
    100.times do |index|
      seed_user(
        id: index + 1,
        login: "country#{index}",
        total_stars: 1_000 - index,
        city: 'Warszawa',
        country: 'Poland'
      )
    end
    seed_user(id: 101, login: 'alice', total_stars: 100, city: 'Kraków', country: 'Poland')
    seed_user(id: 102, login: 'carol', total_stars: 50, city: 'Kraków', country: 'Poland')

    profile = read_model.user_profile('github', 'carol', period_start: period)

    expect(profile.fetch(:elite_rank)).to eq(102)
    expect(profile.fetch(:city_rank)).to eq(2)
    expect(profile.fetch(:profile_badge)).to include(label: 'Kraków Elite', value: '2nd')
  end

  it 'returns a city-only badge for public profiles without current ranking stats' do
    seed_user_record(id: 1, login: 'alumni', city: 'Kraków', country: 'Poland')

    profile = read_model.user_profile('github', 'alumni', period_start: period)

    expect(profile.fetch(:profile_badge)).to include(label: 'Polish Open Source', value: nil, status: 'outside_ranking')
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
    expect(user.fetch(:profile_badge)).to include(label: 'Polish Open Source', value: nil)
    expect(repository).to include(elite_rank: nil)
    expect(read_model.user_profile('github', 'missing', period_start: period)).to be_nil
    expect(read_model.repository_profile('github', 'alice', 'missing', period_start: period)).to be_nil
  end

  it 'lists every public user identity for sitemap rendering' do
    seed_user_record(id: 1, login: 'alice')
    seed_user_record(id: 2, login: 'bob')

    expect(read_model.public_user_identities).to contain_exactly(
      include(platform: 'github', login: 'alice'),
      include(platform: 'github', login: 'bob')
    )
  end

  it 'returns organization profiles, organization repositories, and public organization identities' do
    seed_organization(id: 50, login: 'polish-org', total_stars: 300)
    seed_organization(id: 60, login: 'other-org', total_stars: 150)
    seed_organization_repository(
      id: 501,
      organization_id: 50,
      organization_login: 'polish-org',
      full_name: 'polish-org/toolkit',
      stars: 200
    )

    organization = read_model.organization_profile('github', 'polish-org', period_start: period)
    repository = read_model.organization_repository_profile('github', 'polish-org', 'toolkit', period_start: period)

    expect(organization).to include(login: 'polish-org', elite_rank: 1)
    expect(organization.fetch(:profile_badge)).to include(label: 'Polish Open Source Org', value: '1st')
    expect(organization.fetch(:repositories)).to contain_exactly(
      include(full_name: 'polish-org/toolkit', polish_repo_badge: include(label: 'Polish Org Repo', value: '1st'))
    )
    expect(repository).to include(full_name: 'polish-org/toolkit', elite_rank: 1)
    expect(repository.fetch(:polish_repo_badge)).to include(label: 'Polish Org Repo', value: '1st')
    expect(read_model.public_organization_identities).to contain_exactly(
      include(platform: 'github', login: 'other-org'),
      include(platform: 'github', login: 'polish-org')
    )
  end

  def period
    '2026-04-01'
  end

  def seed_user(id:, login:, total_stars:, period_start: period, city: 'Kraków', country: 'Poland')
    seed_user_record(id: id, login: login, city: city, country: country)
    database.execute(user_stats_sql, [period_start, 'github', id, login, city, country, 1, total_stars, 0, 1,
                                      '2026-05-01T00:10:00Z'])
  end

  def seed_user_record(id:, login:, city: nil, country: nil)
    database.execute(
      <<~SQL.strip,
        INSERT OR IGNORE INTO users(
          platform, github_id, login, city, country, html_url, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
      ['github', id, login, city, country, "https://github.com/#{login}", '2026-05-01T00:01:00Z']
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

  def seed_organization(id:, login:, total_stars:, period_start: period, city: 'Warszawa', country: 'Poland')
    database.execute(
      <<~SQL.strip,
        INSERT OR IGNORE INTO organizations(
          platform, github_id, login, city, country, html_url, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
      ['github', id, login, city, country, "https://github.com/#{login}", '2026-05-01T00:01:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO organization_monthly_stats(
          period_start, platform, organization_github_id, login, city, country, public_repo_count,
          total_stars, monthly_stars_delta, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [period_start, 'github', id, login, city, country, 1, total_stars, 0, '2026-05-01T00:10:00Z']
    )
  end

  def seed_organization_repository(id:, organization_id:, organization_login:, full_name:, stars:)
    database.execute(
      <<~SQL,
        INSERT INTO organization_repositories(
          platform, github_id, organization_github_id, organization_login, name, full_name, html_url, fork,
          archived, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?)
      SQL
      ['github', id, organization_id, organization_login, full_name.split('/').last, full_name,
       "https://github.com/#{full_name}", '2026-05-01T00:01:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO organization_repository_monthly_stats(
          period_start, platform, repository_github_id, organization_github_id, organization_login,
          organization_city, organization_country, stargazers_count, monthly_stars_delta, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [period, 'github', id, organization_id, organization_login, 'Warszawa', 'Poland', stars, 0,
       '2026-05-01T00:10:00Z']
    )
  end
end
