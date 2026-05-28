# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteJobProgressReadModel do
  it 'keeps the operations read model behind the extracted namespace' do
    expect(described_class.superclass).to eq(PolishOpenSourceRank::Infrastructure::SQLiteJobProgress)
  end

  it 'reports independent monthly and package sections with duration estimates' do
    database = open_database
    seed_monthly_progress(database)
    seed_package_progress(database)
    seed_work_events(database)

    progress = described_class.new(database).job_progress(now: Time.parse('2026-05-01T00:10:00Z'))

    expect_section_labels(progress)
    expect_monthly_user_estimates(progress)
    expect(section(progress, 'package repository scans / user')).to include(total: 2, done: 1, pending: 1, failed: 0)
    expect(section(progress, 'registry snapshots / npm')).to include(
      total: 2,
      done: 1,
      pending: 1,
      status_detail: 'active=1, pending=1, not_found=0, rate_limited=0, failed=0'
    )
  end

  it 'marks unfinished monthly sections as failed after the owning run fails' do
    database = open_database
    insert_run = <<~SQL
      INSERT INTO sync_runs(period_start, period_end, status, started_at, finished_at, error)
      VALUES (?, ?, ?, ?, ?, ?)
    SQL
    database.execute(
      insert_run,
      ['2026-04-01', '2026-05-01', 'failed', '2026-05-01T00:00:00Z', '2026-05-01T00:05:00Z', 'Received SIGTERM']
    )
    database.execute(candidate_sql(:candidate_organizations), ['2026-04-01', 'github', 3, 'org', 'pending'])
    event = PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteJobWorkEventRepository.new(database)
    event.record(
      **base_event,
      stage: 'organizations',
      unit_kind: 'organization_candidate',
      subject_label: 'done-org'
    )

    progress = described_class.new(database).job_progress(now: Time.parse('2026-05-01T00:10:00Z'))

    expect(section(progress, 'monthly organizations / github')).to include(
      pending: 1,
      state: 'failed'
    )
  end

  it 'does not report repository retention as pending work after a monthly run finishes' do
    database = open_database
    database.execute(
      'INSERT INTO sync_runs(period_start, period_end, status, started_at, finished_at) VALUES (?, ?, ?, ?, ?)',
      ['2026-04-01', '2026-05-01', 'finished', '2026-05-01T00:00:00Z', '2026-05-01T00:05:00Z']
    )
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 1, 'alice', 'https://github.com/alice', '2026-05-01T00:01:00Z']
    )
    database.execute(repository_sql(:repositories), ['github', 10, 1, 'alice', 'app', 'alice/app'])
    database.execute(user_stats_sql, ['2026-04-01', 'github', 1, 'alice', 2, '2026-05-01T00:01:00Z'])
    database.execute(repository_stats_sql, ['2026-04-01', 'github', 10, 1, 'alice', '2026-05-01T00:01:00Z'])

    progress = described_class.new(database).job_progress(now: Time.parse('2026-05-01T00:10:00Z'))

    expect(section(progress, 'user repositories / github')).to include(
      total: 2,
      done: 2,
      pending: 0,
      state: 'complete'
    )
  end

  def expect_section_labels(progress)
    expect(progress.fetch(:sections).map { |section| section.fetch(:label) }).to include(
      'monthly users / github',
      'monthly organizations / github',
      'user repositories / github',
      'organization repositories / github',
      'package repository scans / user',
      'package manifests / npm',
      'registry packages / npm',
      'registry snapshots / npm'
    )
  end

  def expect_monthly_user_estimates(progress)
    expect(section(progress, 'monthly users / github')).to include(
      total: 2,
      done: 1,
      pending: 1,
      average_ms: 1000,
      median_ms: 1000,
      p95_ms: 1000,
      eta_average_seconds: 1,
      state: 'running'
    )
  end

  def open_database
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'progress.sqlite3')
    ).tap { |sqlite| sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql) }
  end

  def seed_monthly_progress(database)
    database.execute(
      'INSERT INTO sync_runs(period_start, period_end, status, started_at) VALUES (?, ?, ?, ?)',
      ['2026-04-01', '2026-05-01', 'running', '2026-05-01T00:00:00Z']
    )
    database.execute(candidate_sql(:candidate_users), ['2026-04-01', 'github', 1, 'alice', 'processed'])
    database.execute(candidate_sql(:candidate_users), ['2026-04-01', 'github', 2, 'bob', 'pending'])
    database.execute(candidate_sql(:candidate_organizations), ['2026-04-01', 'github', 3, 'org', 'processed'])
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 1, 'alice', 'https://github.com/alice', '2026-05-01T00:01:00Z']
    )
    database.execute(
      'INSERT INTO organizations(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 3, 'org', 'https://github.com/org', '2026-05-01T00:01:00Z']
    )
    database.execute(user_stats_sql, ['2026-04-01', 'github', 1, 'alice', 2, '2026-05-01T00:01:00Z'])
    database.execute(organization_stats_sql, ['2026-04-01', 'github', 3, 'org', 1, '2026-05-01T00:01:00Z'])
    database.execute(repository_sql(:repositories), ['github', 10, 1, 'alice', 'app', 'alice/app'])
    database.execute(repository_stats_sql, ['2026-04-01', 'github', 10, 1, 'alice', '2026-05-01T00:01:00Z'])
    database.execute(repository_sql(:organization_repositories), ['github', 20, 3, 'org', 'tool', 'org/tool'])
    database.execute(organization_repository_stats_sql, ['2026-04-01', 'github', 20, 3, 'org', '2026-05-01T00:01:00Z'])
  end

  def seed_package_progress(database)
    database.execute(
      'INSERT INTO package_crawl_runs(period_start, status, refresh, started_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['2026-04-01', 'running', 0, '2026-05-01T00:00:00Z', '2026-05-01T00:00:00Z']
    )
    database.execute(package_scan_sql, ['2026-04-01', 'user', 'github', 10, 'alice/app', 'scanned'])
    database.execute(package_scan_sql, ['2026-04-01', 'user', 'github', 11, 'alice/lib', 'pending'])
    database.execute(package_manifest_sql, [1, 'npm', 'package.json', 'pkg', 'pkg', 'parsed'])
    database.execute(registry_package_sql, %w[npm pkg pkg active])
    database.execute(registry_package_sql, %w[npm missing missing pending])
    database.execute(registry_snapshot_sql, %w[npm pkg 2026-04-01])
  end

  def seed_work_events(database)
    event = PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteJobWorkEventRepository.new(database)
    event.record(**base_event, stage: 'users', unit_kind: 'user_candidate', subject_label: 'alice')
    event.record(
      **base_event, job_kind: 'packages',
                    stage: 'repository_scan',
                    unit_kind: 'package_repository_scan',
                    subject_label: 'alice/app',
                    duration_ms: 2000
    )
    event.record(
      **base_event, job_kind: 'packages',
                    stage: 'repository_scan',
                    unit_kind: 'package_repository_scan',
                    subject_label: 'alice/lib',
                    finished_at: '2026-05-01T00:00:03Z',
                    duration_ms: 3000
    )
  end

  def section(progress, label)
    progress.fetch(:sections).find { |item| item.fetch(:label) == label }
  end

  def base_event
    {
      period_start: '2026-04-01',
      job_kind: 'monthly',
      stage: 'users',
      unit_kind: 'user_candidate',
      platform: 'github',
      status: 'processed',
      started_at: '2026-05-01T00:00:00Z',
      finished_at: '2026-05-01T00:00:01Z',
      duration_ms: 1000
    }
  end

  def candidate_sql(table)
    <<~SQL
      INSERT INTO #{table}(period_start, platform, github_id, login, source_query, status, updated_at)
      VALUES (?, ?, ?, ?, 'Poland', ?, '2026-05-01T00:01:00Z')
    SQL
  end

  def user_stats_sql
    <<~SQL
      INSERT INTO user_monthly_stats(
        period_start, platform, user_github_id, login, public_repo_count, total_stars,
        monthly_stars_delta, public_activity_count, updated_at
      )
      VALUES (?, ?, ?, ?, ?, 0, 0, 0, ?)
    SQL
  end

  def organization_stats_sql
    <<~SQL
      INSERT INTO organization_monthly_stats(
        period_start, platform, organization_github_id, login, public_repo_count,
        total_stars, monthly_stars_delta, updated_at
      )
      VALUES (?, ?, ?, ?, ?, 0, 0, ?)
    SQL
  end

  def repository_sql(table)
    owner_id = table == :repositories ? 'owner_github_id, owner_login' : 'organization_github_id, organization_login'
    <<~SQL
      INSERT INTO #{table}(
        platform, github_id, #{owner_id}, name, full_name, html_url, fork, archived, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, 'https://example.com/repo', 0, 0, '2026-05-01T00:01:00Z')
    SQL
  end

  def repository_stats_sql
    <<~SQL
      INSERT INTO repository_monthly_stats(
        period_start, platform, repository_github_id, owner_github_id, owner_login,
        stargazers_count, monthly_stars_delta, updated_at
      )
      VALUES (?, ?, ?, ?, ?, 0, 0, ?)
    SQL
  end

  def organization_repository_stats_sql
    <<~SQL
      INSERT INTO organization_repository_monthly_stats(
        period_start, platform, repository_github_id, organization_github_id, organization_login,
        stargazers_count, monthly_stars_delta, updated_at
      )
      VALUES (?, ?, ?, ?, ?, 0, 0, ?)
    SQL
  end

  def package_scan_sql
    <<~SQL
      INSERT INTO package_repository_scans(
        period_start, repository_kind, platform, repository_source_id, full_name, status, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, '2026-05-01T00:01:00Z')
    SQL
  end

  def package_manifest_sql
    <<~SQL
      INSERT INTO package_manifests(
        repository_scan_id, ecosystem, path, package_name, normalized_package_name,
        confidence, parse_status, parser_version, parsed_at
      )
      VALUES (?, ?, ?, ?, ?, 'high', ?, 'v1', '2026-05-01T00:01:00Z')
    SQL
  end

  def registry_package_sql
    <<~SQL
      INSERT INTO registry_packages(
        ecosystem, package_name, normalized_package_name, registry_url, status, updated_at
      )
      VALUES (?, ?, ?, 'https://example.com/package', ?, '2026-05-01T00:01:00Z')
    SQL
  end

  def registry_snapshot_sql
    <<~SQL
      INSERT INTO registry_package_snapshots(
        ecosystem, normalized_package_name, period_start, observed_at
      )
      VALUES (?, ?, ?, '2026-05-01T00:01:00Z')
    SQL
  end
end
