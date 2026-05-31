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

  it 'does not report a user as processed when only part of the repository snapshot exists' do
    seed_user
    seed_user_stats(public_repo_count: 2)
    seed_repository
    seed_repository_stats

    expect(queue.processed_user?(period, 'github', 1)).to be_nil
  end

  it 'reports a user as processed when stored repository rows exceed the public repository count' do
    seed_user
    seed_user_stats(public_repo_count: 2)
    seed_repository(github_id: 10, full_name: 'alice/app')
    seed_repository_stats(repository_github_id: 10, full_name: 'alice/app')
    seed_repository(github_id: 11, full_name: 'alice/app-2')
    seed_repository_stats(repository_github_id: 11, full_name: 'alice/app-2')
    seed_repository(github_id: 12, full_name: 'alice/app-3')
    seed_repository_stats(repository_github_id: 12, full_name: 'alice/app-3')

    expect(queue.processed_user?(period, 'github', 1)).to eq(1)
  end

  it 'records and resolves organization candidates through organization snapshots' do
    queue.record_organization(period, github_id: 11, login: 'polish-org', source_query: 'Poland')
    queue.mark_organization(period, 'polish-org', 'failed', 'temporary')

    expect(queue.pending_organizations(period)).to be_empty
    expect(candidate_organization('polish-org')).to include(
      platform: 'github',
      source_query: 'Poland',
      status: 'failed',
      error: 'temporary'
    )

    seed_organization
    seed_organization_stats(public_repo_count: 1)
    expect(queue.processed_organization?(period, 'github', 11)).to be_nil

    seed_organization_repository
    seed_organization_repository_stats

    expect(queue.processed_organization?(period, 'github', 11)).to eq(1)
    expect(queue.processed_organization?(period, 11)).to eq(1)
  end

  it 'does not report an organization as processed when only part of the repository snapshot exists' do
    seed_organization
    seed_organization_stats(public_repo_count: 2)
    seed_organization_repository
    seed_organization_repository_stats

    expect(queue.processed_organization?(period, 'github', 11)).to be_nil
  end

  it 'reports an organization as processed when stored repository rows exceed the public repository count' do
    seed_organization
    seed_organization_stats(public_repo_count: 2)
    seed_organization_repository(github_id: 110, full_name: 'polish-org/app')
    seed_organization_repository_stats(repository_github_id: 110, full_name: 'polish-org/app')
    seed_organization_repository(github_id: 111, full_name: 'polish-org/app-2')
    seed_organization_repository_stats(repository_github_id: 111, full_name: 'polish-org/app-2')
    seed_organization_repository(github_id: 112, full_name: 'polish-org/app-3')
    seed_organization_repository_stats(repository_github_id: 112, full_name: 'polish-org/app-3')

    expect(queue.processed_organization?(period, 'github', 11)).to eq(1)
  end

  def candidate(login)
    database.fetch_all('SELECT * FROM candidate_users WHERE login = ?', [login]).first
  end

  def candidate_organization(login)
    database.fetch_all('SELECT * FROM candidate_organizations WHERE login = ?', [login]).first
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

  def seed_repository(github_id: 10, full_name: 'alice/app')
    database.execute(
      repository_sql,
      ['github', github_id, 1, 'alice', full_name.split('/').last, full_name, "https://github.com/#{full_name}", 0, 0,
       '2026-05-01T00:01:00Z']
    )
  end

  def seed_repository_stats(repository_github_id: 10, full_name: 'alice/app')
    database.execute(repository_stats_sql, [period.start_date.to_s, 'github', repository_github_id, 1,
                                            full_name.split('/').first, 'Kraków', 'Poland', 10, 1,
                                            '2026-05-01T00:10:00Z'])
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

  def seed_organization
    database.execute(
      'INSERT INTO organizations(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 11, 'polish-org', 'https://github.com/polish-org', '2026-05-01T00:01:00Z']
    )
  end

  def seed_organization_stats(public_repo_count:)
    database.execute(
      <<~SQL,
        INSERT INTO organization_monthly_stats(
          period_start, platform, organization_github_id, login, city, country, public_repo_count,
          total_stars, monthly_stars_delta, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [period.start_date.to_s, 'github', 11, 'polish-org', 'Warszawa', 'Poland', public_repo_count, 10, 1,
       '2026-05-01T00:10:00Z']
    )
  end

  def seed_organization_repository(github_id: 110, full_name: 'polish-org/app')
    database.execute(
      <<~SQL,
        INSERT INTO organization_repositories(
          platform, github_id, organization_github_id, organization_login, name, full_name, html_url, fork,
          archived, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?)
      SQL
      ['github', github_id, 11, 'polish-org', full_name.split('/').last, full_name, "https://github.com/#{full_name}",
       '2026-05-01T00:01:00Z']
    )
  end

  def seed_organization_repository_stats(repository_github_id: 110, full_name: 'polish-org/app')
    values = [
      period.start_date.to_s,
      'github',
      repository_github_id,
      11,
      full_name.split('/').first,
      'Warszawa',
      'Poland',
      10,
      1,
      '2026-05-01T00:10:00Z'
    ]
    database.execute(
      <<~SQL,
        INSERT INTO organization_repository_monthly_stats(
          period_start, platform, repository_github_id, organization_github_id, organization_login,
          organization_city, organization_country, stargazers_count, monthly_stars_delta, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      values
    )
  end
end
