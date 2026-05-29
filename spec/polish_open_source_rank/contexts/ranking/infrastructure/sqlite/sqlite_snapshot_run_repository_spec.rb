# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRunRepository do
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:repository) { described_class.new(database) }

  it 'creates runs with UTC timestamps and resets retryable candidates', :aggregate_failures do
    allow(Time).to receive(:now) { Time.new(2026, 4, 1, 12, 0, 0, '+02:00') }
    seed_candidate(login: 'alice', status: 'failed', error: 'boom')
    seed_candidate(login: 'bob', status: 'processed')

    run_id = repository.create(period)

    expect(run_id).to eq(sync_run.fetch(:id))
    expect(sync_run).to include(
      period_start: '2026-04-01',
      period_end: '2026-05-01',
      status: 'running',
      started_at: '2026-04-01T10:00:00Z',
      finished_at: nil,
      error: nil
    )
    expect(candidate('alice')).to include(status: 'pending', error: nil, updated_at: '2026-04-01T10:00:00Z')
    expect(candidate('bob')).to include(status: 'pending', error: nil, updated_at: '2026-04-01T10:00:00Z')
  end

  it 'does not reopen finished runs without retryable candidates' do
    seed_run(status: 'finished', started_at: '2026-04-01T08:00:00Z', finished_at: '2026-04-01T09:00:00Z')

    expect(repository.create(period)).to be_nil
    expect(sync_run).to include(
      status: 'finished',
      started_at: '2026-04-01T08:00:00Z',
      finished_at: '2026-04-01T09:00:00Z'
    )
  end

  it 'reopens a finished run for explicitly refreshed platforms' do
    allow(Time).to receive(:now) { Time.new(2026, 4, 1, 12, 0, 0, '+02:00') }
    seed_run(status: 'finished', started_at: '2026-04-01T08:00:00Z', finished_at: '2026-04-01T09:00:00Z')
    seed_candidate(login: 'alice', platform: 'github', status: 'processed')
    seed_complete_processed_candidate('alice', platform: 'github')
    seed_candidate(login: 'bob', platform: 'gitlab', status: 'failed', error: 'timeout')

    repository.create(period, refresh_platforms: ['gitlab'])

    expect(sync_run).to include(
      status: 'running',
      started_at: '2026-04-01T10:00:00Z',
      finished_at: nil,
      error: nil
    )
    expect(candidate('alice', platform: 'github')).to include(status: 'processed', error: nil)
    expect(candidate('bob', platform: 'gitlab')).to include(
      status: 'pending',
      error: nil,
      updated_at: '2026-04-01T10:00:00Z'
    )
  end

  it 'marks runs as failed with the original error message' do
    allow(Time).to receive(:now) { Time.new(2026, 4, 1, 12, 0, 0, '+02:00') }
    run_id = seed_run

    repository.fail(run_id, 'GitHubClient::Forbidden: blocked')

    expect(sync_run).to include(
      status: 'failed',
      finished_at: '2026-04-01T10:00:00Z',
      error: 'GitHubClient::Forbidden: blocked'
    )
  end

  it 'restores completed pending candidates when a refresh run fails', :aggregate_failures do
    allow(Time).to receive(:now) { Time.new(2026, 4, 1, 12, 0, 0, '+02:00') }
    run_id = seed_run
    seed_candidate(login: 'alice', status: 'pending')
    seed_complete_processed_candidate('alice', platform: 'github')
    seed_candidate(login: 'bob', status: 'pending')
    seed_organization_candidate(login: 'polish-org', status: 'pending')
    seed_complete_processed_organization_candidate('polish-org', platform: 'github')

    repository.fail(run_id, 'Received SIGTERM')

    expect(candidate('alice')).to include(status: 'processed', error: nil, updated_at: '2026-04-01T10:00:00Z')
    expect(candidate('bob')).to include(status: 'pending')
    expect(organization_candidate('polish-org')).to include(
      status: 'processed',
      error: nil,
      updated_at: '2026-04-01T10:00:00Z'
    )
  end

  it 'marks runs as finished with a UTC timestamp' do
    allow(Time).to receive(:now) { Time.new(2026, 4, 1, 12, 0, 0, '+02:00') }
    run_id = seed_run

    repository.finish(run_id)

    expect(sync_run).to include(status: 'finished', finished_at: '2026-04-01T10:00:00Z')
  end

  it 'reports retryable candidates with optional platform filters' do
    expect(repository.retryable_candidates?(period)).to be(false)

    seed_candidate(login: 'alice', platform: 'github', status: 'pending')
    seed_candidate(login: 'bob', platform: 'gitlab', status: 'processed')

    expect(repository.retryable_candidates?(period)).to be(true)
    expect(repository.retryable_candidates?(period, platforms: ['gitlab'])).to be(true)
    expect(repository.retryable_candidates?(period, platforms: ['codeberg'])).to be(false)
    expect(repository.retryable_candidates?(period, platforms: [])).to be(false)
  end

  it 'treats processed users with incomplete repository coverage as retryable' do
    github_id = seed_candidate(login: 'alice', platform: 'github', status: 'processed')
    seed_incomplete_processed_candidate('alice', platform: 'github', github_id: github_id)

    expect(repository.retryable_candidates?(period)).to be(true)
  end

  it 'does not treat processed users with extra repository rows as retryable' do
    github_id = seed_candidate(login: 'alice', platform: 'github', status: 'processed')
    seed_complete_processed_candidate_with_extra_repository_row('alice', platform: 'github', github_id: github_id)

    expect(repository.retryable_candidates?(period)).to be(false)
  end

  it 'treats processed organizations with incomplete repository coverage as retryable' do
    github_id = seed_organization_candidate(login: 'polish-org', platform: 'github', status: 'processed')
    seed_incomplete_processed_organization_candidate('polish-org', platform: 'github', github_id: github_id)

    expect(repository.retryable_candidates?(period, candidate_types: [:organizations])).to be(true)
  end

  it 'does not treat processed organizations with extra repository rows as retryable' do
    github_id = seed_organization_candidate(login: 'polish-org', platform: 'github', status: 'processed')
    seed_complete_processed_organization_candidate_with_extra_repository_row(
      'polish-org', platform: 'github', github_id: github_id
    )

    expect(repository.retryable_candidates?(period, candidate_types: [:organizations])).to be(false)
  end

  it 'reports retryable candidates with optional candidate type filters' do
    seed_candidate(login: 'alice', platform: 'github', status: 'pending')
    seed_organization_candidate(login: 'polish-org', platform: 'github', status: 'pending')

    expect(repository.retryable_candidates?(period, candidate_types: [:users])).to be(true)
    expect(repository.retryable_candidates?(period, candidate_types: [:organizations])).to be(true)

    database.dataset(:candidate_users).where(login: 'alice').update(status: 'rejected')

    expect(repository.retryable_candidates?(period, candidate_types: [:users])).to be(false)
    expect(repository.retryable_candidates?(period, candidate_types: [:organizations])).to be(true)
    expect(repository.retryable_candidates?(period, candidate_types: [])).to be(false)
  end

  def sync_run
    database.fetch_all('SELECT * FROM sync_runs').first
  end

  def candidate(login, platform: 'github')
    database.fetch_all('SELECT * FROM candidate_users WHERE login = ? AND platform = ?', [login, platform]).first
  end

  def organization_candidate(login, platform: 'github')
    database.fetch_all(
      'SELECT * FROM candidate_organizations WHERE login = ? AND platform = ?',
      [login, platform]
    ).first
  end

  def seed_run(attributes = {})
    defaults = {
      status: 'running',
      started_at: '2026-04-01T00:00:00Z',
      finished_at: nil,
      error: nil
    }
    attributes = defaults.merge(attributes)
    status = attributes.fetch(:status)
    started_at = attributes.fetch(:started_at)
    finished_at = attributes[:finished_at]
    error = attributes[:error]

    database.execute(
      <<~SQL,
        INSERT INTO sync_runs(period_start, period_end, status, started_at, finished_at, error)
        VALUES (?, ?, ?, ?, ?, ?)
      SQL
      ['2026-04-01', '2026-05-01', status, started_at, finished_at, error]
    )
    sync_run.fetch(:id)
  end

  def seed_candidate(attributes)
    defaults = {
      platform: 'github',
      error: nil,
      updated_at: '2026-04-01T00:00:00Z'
    }
    attributes = defaults.merge(attributes)
    login = attributes.fetch(:login)
    platform = attributes.fetch(:platform)
    status = attributes.fetch(:status)
    error = attributes[:error]
    updated_at = attributes.fetch(:updated_at)
    github_id = ((login.hash.abs % 1000) + 1)

    database.execute(
      <<~SQL,
        INSERT INTO candidate_users(
          period_start, platform, github_id, login, source_query, status, error, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      ['2026-04-01', platform, github_id, login, 'poland', status, error, updated_at]
    )
    github_id
  end

  def seed_organization_candidate(attributes)
    defaults = {
      platform: 'github',
      error: nil,
      updated_at: '2026-04-01T00:00:00Z'
    }
    attributes = defaults.merge(attributes)
    login = attributes.fetch(:login)
    github_id = ((login.hash.abs % 1000) + 1)

    database.execute(
      <<~SQL,
        INSERT INTO candidate_organizations(
          period_start, platform, github_id, login, source_query, status, error, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [
        '2026-04-01', attributes.fetch(:platform), github_id, login, 'poland',
        attributes.fetch(:status), attributes[:error], attributes.fetch(:updated_at)
      ]
    )
    github_id
  end

  def seed_complete_processed_candidate(login, platform:)
    github_id = ((login.hash.abs % 1000) + 1)

    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      [platform, github_id, login, "https://#{platform}.example.com/#{login}", '2026-04-01T00:00:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO user_monthly_stats(
          period_start, platform, user_github_id, login, public_repo_count,
          total_stars, monthly_stars_delta, public_activity_count, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      ['2026-04-01', platform, github_id, login, 0, 0, 0, 0, '2026-04-01T00:00:00Z']
    )
  end

  def seed_incomplete_processed_candidate(login, platform:, github_id:)
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      [platform, github_id, login, "https://#{platform}.example.com/#{login}", '2026-04-01T00:00:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO user_monthly_stats(
          period_start, platform, user_github_id, login, public_repo_count,
          total_stars, monthly_stars_delta, public_activity_count, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      ['2026-04-01', platform, github_id, login, 2, 1, 0, 0, '2026-04-01T00:00:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO repositories(
          platform, github_id, owner_github_id, owner_login, name, full_name, html_url, fork, archived, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [platform, github_id + 10, github_id, login, 'app', "#{login}/app", "https://#{platform}.example.com/#{login}/app",
       0, 0, '2026-04-01T00:00:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO repository_monthly_stats(
          period_start, platform, repository_github_id, owner_github_id, owner_login, owner_city,
          owner_country, stargazers_count, monthly_stars_delta, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      ['2026-04-01', platform, github_id + 10, github_id, login, 'Kraków', 'Poland', 1, 0, '2026-04-01T00:00:00Z']
    )
  end

  def seed_complete_processed_candidate_with_extra_repository_row(login, platform:, github_id:)
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      [platform, github_id, login, "https://#{platform}.example.com/#{login}", '2026-04-01T00:00:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO user_monthly_stats(
          period_start, platform, user_github_id, login, public_repo_count,
          total_stars, monthly_stars_delta, public_activity_count, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      ['2026-04-01', platform, github_id, login, 2, 1, 0, 0, '2026-04-01T00:00:00Z']
    )

    3.times do |index|
      repository_id = github_id + 10 + index
      suffix = index.zero? ? 'app' : "app-#{index + 1}"
      database.execute(
        <<~SQL,
          INSERT INTO repositories(
            platform, github_id, owner_github_id, owner_login, name, full_name, html_url, fork, archived, updated_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        [platform, repository_id, github_id, login, suffix, "#{login}/#{suffix}",
         "https://#{platform}.example.com/#{login}/#{suffix}", 0, 0, '2026-04-01T00:00:00Z']
      )
      database.execute(
        <<~SQL,
          INSERT INTO repository_monthly_stats(
            period_start, platform, repository_github_id, owner_github_id, owner_login, owner_city,
            owner_country, stargazers_count, monthly_stars_delta, updated_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        ['2026-04-01', platform, repository_id, github_id, login, 'Kraków', 'Poland', 1, 0, '2026-04-01T00:00:00Z']
      )
    end
  end

  def seed_complete_processed_organization_candidate(login, platform:)
    github_id = ((login.hash.abs % 1000) + 1)

    database.execute(
      'INSERT INTO organizations(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      [platform, github_id, login, "https://#{platform}.example.com/#{login}", '2026-04-01T00:00:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO organization_monthly_stats(
          period_start, platform, organization_github_id, login, public_repo_count,
          total_stars, monthly_stars_delta, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      ['2026-04-01', platform, github_id, login, 0, 0, 0, '2026-04-01T00:00:00Z']
    )
  end

  def seed_incomplete_processed_organization_candidate(login, platform:, github_id:)
    database.execute(
      'INSERT INTO organizations(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      [platform, github_id, login, "https://#{platform}.example.com/#{login}", '2026-04-01T00:00:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO organization_monthly_stats(
          period_start, platform, organization_github_id, login, public_repo_count,
          total_stars, monthly_stars_delta, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      ['2026-04-01', platform, github_id, login, 2, 1, 0, '2026-04-01T00:00:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO organization_repositories(
          platform, github_id, organization_github_id, organization_login, name, full_name, html_url, fork,
          archived, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [platform, github_id + 10, github_id, login, 'app', "#{login}/app",
       "https://#{platform}.example.com/#{login}/app", 0, 0, '2026-04-01T00:00:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO organization_repository_monthly_stats(
          period_start, platform, repository_github_id, organization_github_id, organization_login,
          organization_city, organization_country, stargazers_count, monthly_stars_delta, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      ['2026-04-01', platform, github_id + 10, github_id, login, 'Warszawa', 'Poland', 1, 0,
       '2026-04-01T00:00:00Z']
    )
  end

  def seed_complete_processed_organization_candidate_with_extra_repository_row(login, platform:, github_id:)
    database.execute(
      'INSERT INTO organizations(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      [platform, github_id, login, "https://#{platform}.example.com/#{login}", '2026-04-01T00:00:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO organization_monthly_stats(
          period_start, platform, organization_github_id, login, public_repo_count,
          total_stars, monthly_stars_delta, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      ['2026-04-01', platform, github_id, login, 2, 1, 0, '2026-04-01T00:00:00Z']
    )

    3.times do |index|
      repository_id = github_id + 10 + index
      suffix = index.zero? ? 'app' : "app-#{index + 1}"
      database.execute(
        <<~SQL,
          INSERT INTO organization_repositories(
            platform, github_id, organization_github_id, organization_login, name, full_name, html_url, fork,
            archived, updated_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        [platform, repository_id, github_id, login, suffix, "#{login}/#{suffix}",
         "https://#{platform}.example.com/#{login}/#{suffix}", 0, 0, '2026-04-01T00:00:00Z']
      )
      database.execute(
        <<~SQL,
          INSERT INTO organization_repository_monthly_stats(
            period_start, platform, repository_github_id, organization_github_id, organization_login,
            organization_city, organization_country, stargazers_count, monthly_stars_delta, updated_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        ['2026-04-01', platform, repository_id, github_id, login, 'Warszawa', 'Poland', 1, 0,
         '2026-04-01T00:00:00Z']
      )
    end
  end
end
