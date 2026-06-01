# frozen_string_literal: true

RSpec.describe 'SQLitePublicSnapshotPublicationRepository' do
  let(:repository_class) do
    PolishOpenSourceRank::Contexts::Publication::Infrastructure::SQLite::SQLitePublicSnapshotPublicationRepository
  end
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:backup_root) { Dir.mktmpdir }
  let(:clock) { -> { Time.utc(2026, 6, 1, 12, 0, 0) } }
  let(:repository) { repository_class.new(database, clock: clock, backup_root: backup_root) }

  it 'promotes a verified snapshot atomically and creates a database backup' do
    seed_publishable_month('2026-04-01')
    seed_publishable_month('2026-05-01')
    repository.publish('2026-04-01')

    repository.publish('2026-05-01')

    expect(publication('2026-04-01')).to include(status: 'superseded')
    expect(publication('2026-05-01')).to include(
      status: 'published',
      previous_period_start: '2026-04-01',
      published_at: '2026-06-01T12:00:00Z'
    )
    expect(File.exist?(publication('2026-05-01').fetch(:backup_path))).to be(true)
  end

  it 'rejects incomplete snapshots and keeps the failure visible' do
    seed_monthly_run('2026-05-01', status: 'running')

    expect { repository.verify('2026-05-01') }.to raise_error(
      repository_class::VerificationFailed,
      /monthly rankings are not finished/
    )
    expect(publication('2026-05-01')).to include(status: 'staged', error: include('monthly rankings'))
  end

  it 'rejects snapshots while package crawl data is still running' do
    seed_publishable_month('2026-05-01')
    seed_package_run('2026-05-01', ecosystem: 'rubygems', status: 'running')

    expect { repository.verify('2026-05-01') }.to raise_error(
      repository_class::VerificationFailed,
      /package crawls are not finished/
    )
  end

  it 'rolls back to the previous published snapshot without deleting data' do
    seed_publishable_month('2026-04-01')
    seed_publishable_month('2026-05-01')
    repository.publish('2026-04-01')
    repository.publish('2026-05-01')

    expect(repository.rollback).to eq('2026-04-01')

    expect(publication('2026-05-01')).to include(status: 'rolled_back')
    expect(publication('2026-04-01')).to include(status: 'published')
  end

  def publication(period_start)
    database.fetch_all(
      'SELECT * FROM public_snapshot_publications WHERE period_start = ?',
      [period_start]
    ).first
  end

  def seed_publishable_month(period_start)
    seed_monthly_run(period_start)
    seed_user
    seed_organization
    seed_user_stats(period_start)
    seed_repository_stats(period_start)
    seed_organization_stats(period_start)
    seed_organization_repository_stats(period_start)
    seed_package_run(period_start)
  end

  def seed_monthly_run(period_start, status: 'finished')
    database.execute(
      'INSERT INTO sync_runs(period_start, period_end, status, started_at, finished_at) VALUES (?, ?, ?, ?, ?)',
      [
        period_start, Date.parse(period_start).next_month.to_s, status,
        '2026-06-01T10:00:00Z', '2026-06-01T11:00:00Z'
      ]
    )
  end

  def seed_user
    database.execute(
      'INSERT OR IGNORE INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 1, 'alice', 'https://github.com/alice', '2026-06-01T00:00:00Z']
    )
  end

  def seed_organization
    database.execute(
      'INSERT OR IGNORE INTO organizations(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 2, 'org', 'https://github.com/org', '2026-06-01T00:00:00Z']
    )
  end

  def seed_user_stats(period_start)
    database.execute(<<~SQL, [period_start])
      INSERT INTO user_monthly_stats(
        period_start, platform, user_github_id, login, city, country, public_repo_count,
        total_stars, monthly_stars_delta, merged_pull_requests_count, updated_at
      )
      VALUES (?, 'github', 1, 'alice', 'Kraków', 'Poland', 1, 10, 1, 1, '2026-06-01T00:00:00Z')
    SQL
  end

  def seed_repository_stats(period_start)
    repository_values = [
      'github', 10, 1, 'alice', 'app', 'alice/app',
      'https://github.com/alice/app', 0, 0, '2026-06-01T00:00:00Z'
    ]
    database.execute(
      <<~SQL,
        INSERT OR IGNORE INTO repositories(
          platform, github_id, owner_github_id, owner_login, name, full_name, html_url, fork, archived, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      repository_values
    )
    database.execute(<<~SQL, [period_start])
      INSERT INTO repository_monthly_stats(
        period_start, platform, repository_github_id, owner_github_id, owner_login, owner_city, owner_country,
        stargazers_count, monthly_stars_delta, updated_at
      )
      VALUES (?, 'github', 10, 1, 'alice', 'Kraków', 'Poland', 10, 1, '2026-06-01T00:00:00Z')
    SQL
  end

  def seed_organization_stats(period_start)
    database.execute(<<~SQL, [period_start])
      INSERT INTO organization_monthly_stats(
        period_start, platform, organization_github_id, login, city, country, public_repo_count,
        total_stars, monthly_stars_delta, merged_pull_requests_count, members_count, updated_at
      )
      VALUES (?, 'github', 2, 'org', 'Warszawa', 'Poland', 1, 20, 2, 1, 3, '2026-06-01T00:00:00Z')
    SQL
  end

  def seed_organization_repository_stats(period_start)
    repository_values = [
      'github', 20, 2, 'org', 'tool', 'org/tool',
      'https://github.com/org/tool', 0, 0, '2026-06-01T00:00:00Z'
    ]
    database.execute(
      <<~SQL,
        INSERT OR IGNORE INTO organization_repositories(
          platform, github_id, organization_github_id, organization_login, name, full_name, html_url, fork,
          archived, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      repository_values
    )
    database.execute(<<~SQL, [period_start])
      INSERT INTO organization_repository_monthly_stats(
        period_start, platform, repository_github_id, organization_github_id, organization_login,
        organization_city, organization_country, stargazers_count, monthly_stars_delta, updated_at
      )
      VALUES (?, 'github', 20, 2, 'org', 'Warszawa', 'Poland', 20, 2, '2026-06-01T00:00:00Z')
    SQL
  end

  def seed_package_run(period_start, ecosystem: 'npm', status: 'finished')
    database.execute(<<~SQL, [period_start, ecosystem, status])
      INSERT INTO package_crawl_runs(period_start, ecosystem, status, started_at, finished_at, updated_at)
      VALUES (?, ?, ?, '2026-06-01T00:00:00Z', '2026-06-01T00:10:00Z', '2026-06-01T00:10:00Z')
    SQL
  end
end
