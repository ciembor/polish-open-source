# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageRepositoryQueue do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'package_queue.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:clock) { -> { Time.utc(2026, 5, 23, 11, 0, 0) } }
  let(:queue) { described_class.new(database, clock: clock) }
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }

  it 'enqueues user and organization repositories by package scan priority' do
    seed_user(id: 1, login: 'alice')
    seed_user_repository(id: 101, owner_id: 1, owner: 'alice', full_name: 'alice/stable', stars: 120, delta: 0)
    seed_user_repository(id: 102, owner_id: 1, owner: 'alice', full_name: 'alice/trending', stars: 3, delta: 8)
    seed_user_repository(id: 103, owner_id: 1, owner: 'alice', full_name: 'alice/small', stars: 8, delta: 0)
    seed_user_repository(id: 104, owner_id: 1, owner: 'alice', full_name: 'alice/fork', stars: 200, delta: 0, fork: 1)
    seed_user_repository(
      id: 105, owner_id: 1, owner: 'alice', full_name: 'alice/archived', stars: 200, delta: 0, archived: 1
    )
    seed_organization(id: 2, login: 'polish-org')
    seed_organization_repository(
      id: 201, organization_id: 2, organization: 'polish-org', full_name: 'polish-org/pkg', stars: 90, delta: 4
    )

    queue.enqueue(period, limit: 10)

    expect(scans.map { |scan| scan.fetch(:full_name) }).to eq(
      ['alice/stable', 'polish-org/pkg', 'alice/trending', 'alice/small']
    )
    expect(scans.map { |scan| scan.fetch(:repository_kind) }).to eq(%w[user organization user user])
    expect(scans).to all(include(status: 'pending', updated_at: '2026-05-23T11:00:00Z'))
  end

  it 'treats all as an unbounded enqueue and pending scan limit' do
    seed_user(id: 1, login: 'alice')
    seed_user_repository(id: 101, owner_id: 1, owner: 'alice', full_name: 'alice/one', stars: 20, delta: 0)
    seed_user_repository(id: 102, owner_id: 1, owner: 'alice', full_name: 'alice/two', stars: 10, delta: 0)

    queue.enqueue(period, limit: 'all')

    expect(scans.map { |scan| scan.fetch(:full_name) }).to eq(%w[alice/one alice/two])
    expect(queue.pending(period, limit: 'all').map { |scan| scan.fetch(:full_name) }).to eq(%w[alice/one alice/two])
  end

  it 'keeps enqueue idempotent and can include forks explicitly' do
    seed_user(id: 1, login: 'alice')
    seed_user_repository(id: 101, owner_id: 1, owner: 'alice', full_name: 'alice/fork', stars: 120, delta: 0, fork: 1)

    queue.enqueue(period, limit: 10)
    queue.enqueue(period, limit: 10)
    expect(scans).to be_empty

    queue.enqueue(period, limit: 10, include_forks: true)
    queue.enqueue(period, limit: 10, include_forks: true)

    expect(scans.map { |scan| scan.fetch(:full_name) }).to eq(['alice/fork'])
  end

  it 'returns pending and failed scans and records scan lifecycle transitions' do
    seed_user(id: 1, login: 'alice')
    seed_user_repository(id: 101, owner_id: 1, owner: 'alice', full_name: 'alice/app', stars: 20, delta: 0)
    queue.enqueue(period, limit: 10)
    scan_id = scans.first.fetch(:id)

    queue.mark_processing(scan_id)
    expect(queue.pending(period, limit: 10)).to be_empty

    queue.mark_failed(scan_id, 'tree unavailable')
    expect(queue.pending(period, limit: 10, ecosystem: 'npm').map { |scan| scan.fetch(:id) }).to eq([scan_id])

    queue.mark_unavailable(scan_id, 'repository unavailable')
    expect(queue.pending(period, limit: 10).map { |scan| scan.fetch(:id) }).to be_empty
    expect(queue.pending(period, limit: 10, refresh: true).map { |scan| scan.fetch(:id) }).to eq([scan_id])

    queue.mark_processing(scan_id)
    queue.mark_scanned(scan_id, tree_sha: 'abc123', tree_truncated: true, manifest_count: 2)

    expect(scan(scan_id)).to include(
      status: 'scanned',
      tree_sha: 'abc123',
      tree_truncated: 1,
      manifest_count: 2,
      checked_at: '2026-05-23T11:00:00Z',
      error: nil
    )
    expect(queue.pending(period, limit: 10)).to be_empty
  end

  it 'includes already scanned repositories when refreshing manifest detection' do
    seed_user(id: 1, login: 'alice')
    seed_user_repository(id: 101, owner_id: 1, owner: 'alice', full_name: 'alice/app', stars: 20, delta: 0)
    queue.enqueue(period, limit: 10)
    scan_id = scans.first.fetch(:id)
    queue.mark_scanned(scan_id, tree_sha: 'abc123', tree_truncated: false, manifest_count: 1)

    expect(queue.pending(period, limit: 10)).to be_empty
    expect(queue.pending(period, limit: 10, refresh: true).map { |scan| scan.fetch(:id) }).to eq([scan_id])
  end

  it 'retries scanned repositories with failed manifests from an older parser version' do
    seed_user(id: 1, login: 'alice')
    seed_user_repository(id: 101, owner_id: 1, owner: 'alice', full_name: 'alice/app', stars: 20, delta: 0)
    queue.enqueue(period, limit: 10)
    scan_id = scans.first.fetch(:id)
    queue.mark_scanned(scan_id, tree_sha: 'abc123', tree_truncated: false, manifest_count: 1)
    seed_manifest(scan_id, ecosystem: 'npm', parse_status: 'failed', parser_version: 'manifest-parser-v1')

    expect(queue.pending(period, limit: 10, ecosystem: 'npm').map { |scan| scan.fetch(:id) }).to eq([scan_id])
    expect(queue.pending(period, limit: 10, ecosystem: 'packagist')).to be_empty
  end

  it 'does not keep retrying failed manifests from the current parser version' do
    seed_user(id: 1, login: 'alice')
    seed_user_repository(id: 101, owner_id: 1, owner: 'alice', full_name: 'alice/app', stars: 20, delta: 0)
    queue.enqueue(period, limit: 10)
    scan_id = scans.first.fetch(:id)
    queue.mark_scanned(scan_id, tree_sha: 'abc123', tree_truncated: false, manifest_count: 1)
    seed_manifest(
      scan_id,
      ecosystem: 'npm',
      parse_status: 'failed',
      parser_version: PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageManifestRepository::PARSER_VERSION
    )

    expect(queue.pending(period, limit: 10, ecosystem: 'npm')).to be_empty
  end

  it 'returns interrupted processing scans to the retryable queue' do
    seed_processing_scan(full_name: 'alice/stale', updated_at: '2026-05-23T09:59:59Z')
    seed_processing_scan(full_name: 'alice/current', updated_at: '2026-05-23T10:30:00Z', repository_source_id: 2)

    expect(queue.reset_stale_processing(period)).to eq(1)

    expect(scan_by_name('alice/stale')).to include(
      status: 'failed',
      error: 'processing scan was interrupted and will be retried',
      updated_at: '2026-05-23T11:00:00Z'
    )
    expect(scan_by_name('alice/current')).to include(status: 'processing')
    expect(queue.pending(period, limit: 10).map { |scan| scan.fetch(:full_name) }).to eq(['alice/stale'])
  end

  it 'translates transient SQLite write failures to retryable scan failures' do
    allow(database).to receive(:transaction)
      .and_raise(Sequel::DatabaseError, 'SQLite3::BusyException: database is locked')

    expect { queue.mark_processing(1) }.to raise_error(
      PolishOpenSourceRank::Contexts::Packages::Application::RetryableRepositoryScanFailure,
      'Retryable SQLite persistence failure: SQLite3::BusyException: database is locked'
    )
  end

  it 'reraises non-retryable SQLite write failures' do
    allow(database).to receive(:transaction)
      .and_raise(Sequel::DatabaseError, 'SQLite3::SQLException: malformed database schema')

    expect { queue.mark_processing(1) }.to raise_error(
      Sequel::DatabaseError,
      'SQLite3::SQLException: malformed database schema'
    )
  end

  it 'rejects unsupported ecosystem filters' do
    expect do
      queue.pending(period, limit: 10, ecosystem: 'unknown')
    end.to raise_error(ArgumentError, 'Unsupported package ecosystem: unknown')
  end

  def scans
    database.fetch_all('SELECT * FROM package_repository_scans ORDER BY id ASC')
  end

  def scan(scan_id)
    database.fetch_all('SELECT * FROM package_repository_scans WHERE id = ?', [scan_id]).first
  end

  def scan_by_name(full_name)
    database.fetch_all('SELECT * FROM package_repository_scans WHERE full_name = ?', [full_name]).first
  end

  def seed_processing_scan(full_name:, updated_at:, repository_source_id: 1)
    database.execute(
      <<~SQL,
        INSERT INTO package_repository_scans(
          period_start, repository_kind, platform, repository_source_id, full_name, status, updated_at
        )
        VALUES (?, 'user', 'github', ?, ?, 'processing', ?)
      SQL
      [period.start_date.to_s, repository_source_id, full_name, updated_at]
    )
  end

  def seed_manifest(scan_id, ecosystem:, parse_status:, parser_version:)
    database.dataset(:package_manifests).insert(
      repository_scan_id: scan_id,
      ecosystem: ecosystem,
      path: ecosystem == 'npm' ? 'package.json' : 'manifest',
      confidence: 'low',
      parse_status: parse_status,
      parser_version: parser_version,
      metadata_json: '{}',
      parsed_at: '2026-05-23T11:00:00Z'
    )
  end

  def seed_user(id:, login:)
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', id, login, "https://github.com/#{login}", '2026-05-01T00:00:00Z']
    )
  end

  def seed_organization(id:, login:)
    database.execute(
      'INSERT INTO organizations(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', id, login, "https://github.com/#{login}", '2026-05-01T00:00:00Z']
    )
  end

  def seed_user_repository(attributes)
    database.execute(user_repository_sql, repository_values(attributes))
    database.execute(user_repository_stats_sql, repository_stats_values(attributes, owner_country: 'Poland'))
  end

  def seed_organization_repository(attributes)
    database.execute(organization_repository_sql, organization_repository_values(attributes))
    database.execute(
      organization_repository_stats_sql,
      organization_repository_stats_values(attributes, organization_country: 'Poland')
    )
  end

  def repository_values(attributes)
    [
      'github', attributes.fetch(:id), attributes.fetch(:owner_id), attributes.fetch(:owner),
      attributes.fetch(:full_name).split('/').last, attributes.fetch(:full_name),
      "https://github.com/#{attributes.fetch(:full_name)}", attributes.fetch(:fork, 0),
      attributes.fetch(:archived, 0), '2026-05-01T00:00:00Z'
    ]
  end

  def organization_repository_values(attributes)
    [
      'github', attributes.fetch(:id), attributes.fetch(:organization_id), attributes.fetch(:organization),
      attributes.fetch(:full_name).split('/').last, attributes.fetch(:full_name),
      "https://github.com/#{attributes.fetch(:full_name)}", attributes.fetch(:fork, 0),
      attributes.fetch(:archived, 0), '2026-05-01T00:00:00Z'
    ]
  end

  def repository_stats_values(attributes, owner_country:)
    [
      period.start_date.to_s, 'github', attributes.fetch(:id), attributes.fetch(:owner_id), attributes.fetch(:owner),
      'Warszawa', owner_country, attributes.fetch(:stars), attributes.fetch(:delta), '2026-05-01T00:00:00Z'
    ]
  end

  def organization_repository_stats_values(attributes, organization_country:)
    [
      period.start_date.to_s, 'github', attributes.fetch(:id), attributes.fetch(:organization_id),
      attributes.fetch(:organization), 'Warszawa', organization_country, attributes.fetch(:stars),
      attributes.fetch(:delta), '2026-05-01T00:00:00Z'
    ]
  end

  def user_repository_sql
    <<~SQL
      INSERT INTO repositories(
        platform, github_id, owner_github_id, owner_login, name, full_name, html_url, fork, archived, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end

  def user_repository_stats_sql
    <<~SQL
      INSERT INTO repository_monthly_stats(
        period_start, platform, repository_github_id, owner_github_id, owner_login, owner_city,
        owner_country, stargazers_count, monthly_stars_delta, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end

  def organization_repository_sql
    <<~SQL
      INSERT INTO organization_repositories(
        platform, github_id, organization_github_id, organization_login, name, full_name, html_url, fork,
        archived, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end

  def organization_repository_stats_sql
    <<~SQL
      INSERT INTO organization_repository_monthly_stats(
        period_start, platform, repository_github_id, organization_github_id, organization_login,
        organization_city, organization_country, stargazers_count, monthly_stars_delta, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end
end
