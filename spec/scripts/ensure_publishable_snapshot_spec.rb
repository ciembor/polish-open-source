# frozen_string_literal: true

require 'open3'

RSpec.describe Pathname do
  describe 'ensure_publishable_snapshot.py' do
    it 'blocks publication when package repository scans are active' do
      database_path = File.join(Dir.mktmpdir, 'publishable.sqlite3')
      script_path = PolishOpenSourceRank.root.join('scripts/ensure_publishable_snapshot.py')
      seed_database(database_path, scan_status: 'pending')

      _stdout, stderr, status = Open3.capture3(script_env(database_path), 'python3', script_path.to_s)

      expect(status.exitstatus).to eq(75)
      expect(stderr).to include('package crawls are not finished')
      expect(stderr).to include('1 active scans')
    end

    it 'allows publication when the latest package crawl succeeded after an older failure' do
      database_path = File.join(Dir.mktmpdir, 'publishable.sqlite3')
      script_path = PolishOpenSourceRank.root.join('scripts/ensure_publishable_snapshot.py')
      seed_database(database_path, scan_status: 'unavailable')
      database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(database_path)
      seed_package_run(database, status: 'failed', started_at: '2026-06-01T00:30:00Z')
      seed_package_run(database, status: 'finished', started_at: '2026-06-01T01:00:00Z')

      stdout, stderr, status = Open3.capture3(script_env(database_path), 'python3', script_path.to_s)

      expect(status.success?).to be(true), stderr
      expect(stdout).to include('Snapshot 2026-05-01 is publishable')
    end

    it 'allows publication when package repository scans are terminal' do
      database_path = File.join(Dir.mktmpdir, 'publishable.sqlite3')
      script_path = PolishOpenSourceRank.root.join('scripts/ensure_publishable_snapshot.py')
      seed_database(database_path, scan_status: 'unavailable')

      stdout, stderr, status = Open3.capture3(script_env(database_path), 'python3', script_path.to_s)

      expect(status.success?).to be(true), stderr
      expect(stdout).to include('Snapshot 2026-05-01 is publishable')
    end
  end

  def seed_database(path, scan_status:)
    database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(path)
    database.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    seed_monthly_run(database)
    seed_ranking_data(database)
    seed_package_run(database)
    seed_package_scan(database, scan_status)
  end

  def seed_monthly_run(database)
    database.execute(
      'INSERT INTO sync_runs(period_start, period_end, status, started_at, finished_at) VALUES (?, ?, ?, ?, ?)',
      ['2026-05-01', '2026-06-01', 'finished', '2026-06-01T10:00:00Z', '2026-06-01T11:00:00Z']
    )
  end

  def seed_ranking_data(database)
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 1, 'alice', 'https://github.com/alice', '2026-06-01T00:00:00Z']
    )
    database.execute(
      'INSERT INTO organizations(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 2, 'org', 'https://github.com/org', '2026-06-01T00:00:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO repositories(
          platform, github_id, owner_github_id, owner_login, name, full_name, html_url, fork, archived, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      ['github', 10, 1, 'alice', 'app', 'alice/app', 'https://github.com/alice/app', 0, 0, '2026-06-01T00:00:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO organization_repositories(
          platform, github_id, organization_github_id, organization_login, name, full_name, html_url, fork, archived,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      ['github', 20, 2, 'org', 'tool', 'org/tool', 'https://github.com/org/tool', 0, 0, '2026-06-01T00:00:00Z']
    )
    seed_stats(database)
  end

  def seed_stats(database)
    database.execute(<<~SQL)
      INSERT INTO user_monthly_stats(
        period_start, platform, user_github_id, login, public_repo_count, total_stars,
        monthly_stars_delta, merged_pull_requests_count, updated_at
      ) VALUES ('2026-05-01', 'github', 1, 'alice', 1, 10, 1, 1, '2026-06-01T00:00:00Z')
    SQL
    database.execute(<<~SQL)
      INSERT INTO organization_monthly_stats(
        period_start, platform, organization_github_id, login, public_repo_count, total_stars,
        monthly_stars_delta, merged_pull_requests_count, members_count, updated_at
      ) VALUES ('2026-05-01', 'github', 2, 'org', 1, 20, 2, 1, 3, '2026-06-01T00:00:00Z')
    SQL
    database.execute(<<~SQL)
      INSERT INTO repository_monthly_stats(
        period_start, platform, repository_github_id, owner_github_id, owner_login,
        stargazers_count, monthly_stars_delta, updated_at
      ) VALUES ('2026-05-01', 'github', 10, 1, 'alice', 10, 1, '2026-06-01T00:00:00Z')
    SQL
    database.execute(<<~SQL)
      INSERT INTO organization_repository_monthly_stats(
        period_start, platform, repository_github_id, organization_github_id, organization_login,
        stargazers_count, monthly_stars_delta, updated_at
      ) VALUES ('2026-05-01', 'github', 20, 2, 'org', 20, 2, '2026-06-01T00:00:00Z')
    SQL
  end

  def seed_package_run(database, status: 'finished', started_at: '2026-06-01T00:00:00Z')
    database.execute(<<~SQL, [status, started_at])
      INSERT INTO package_crawl_runs(period_start, ecosystem, status, started_at, finished_at, updated_at)
      VALUES ('2026-05-01', 'npm', ?, ?, '2026-06-01T00:10:00Z', '2026-06-01T00:10:00Z')
    SQL
  end

  def seed_package_scan(database, status)
    database.execute(<<~SQL, [status])
      INSERT INTO package_repository_scans(
        period_start, repository_kind, platform, repository_source_id, full_name, status, updated_at
      )
      VALUES ('2026-05-01', 'user', 'github', 10, 'alice/app', ?, '2026-06-01T00:10:00Z')
    SQL
  end

  def script_env(database_path)
    {
      'DATABASE_URL' => "sqlite://#{database_path}",
      'PUBLISH_PERIOD_START' => '2026-05-01'
    }
  end
end
