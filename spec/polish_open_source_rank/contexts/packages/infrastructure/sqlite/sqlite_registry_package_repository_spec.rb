# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLiteRegistryPackageRepository do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'registry_packages.sqlite3')
    ).tap { |sqlite| sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql) }
  end
  let(:clock) { -> { Time.utc(2026, 5, 23, 13, 0, 0) } }
  let(:repository) { described_class.new(database, clock: clock) }
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }

  it 'resolves parsed manifests to registry packages and links' do
    seed_scan
    seed_manifest(package_name: '@Scope/Tool', normalized_package_name: '@scope/tool')

    repository.resolve_from_manifests(period, ecosystem: 'npm', limit: 10)

    expect(registry_packages.first).to include(
      ecosystem: 'npm',
      package_name: '@Scope/Tool',
      normalized_package_name: '@scope/tool',
      status: 'pending'
    )
    expect(registry_links.first).to include(match_confidence: 'high', matched: 1)
  end

  it 'records successful snapshots and skips already snapshotted packages unless refreshed' do
    seed_pending_package

    repository.record_fetch_result(period, registry_packages.first, successful_result)

    expect(repository.packages_to_fetch(period, ecosystem: 'npm', limit: 10, refresh: false)).to be_empty
    expect(repository.packages_to_fetch(period, ecosystem: 'npm', limit: 10, refresh: true).length).to eq(1)
    expect(registry_packages.first).to include(status: 'active', latest_version: '1.2.3')
    expect(registry_snapshots.first).to include(downloads_30d: 55, downloads_7d: nil)
  end

  it 'records failed fetches without creating a snapshot' do
    seed_pending_package
    failure = PolishOpenSourceRank::Contexts::Packages::Domain::RegistryFetchResult.new(
      status: 'rate_limited',
      error: 'too many requests',
      retry_after: 30
    )

    repository.record_fetch_result(period, registry_packages.first, failure)

    expect(registry_packages.first).to include(status: 'rate_limited', error: 'too many requests')
    expect(registry_snapshots).to be_empty
  end

  def seed_scan
    database.execute(
      <<~SQL,
        INSERT INTO package_repository_scans(
          period_start, repository_kind, platform, repository_source_id, full_name, status, updated_at
        )
        VALUES (?, 'user', 'github', 1, 'alice/app', 'scanned', ?)
      SQL
      [period.start_date.to_s, '2026-05-23T12:00:00Z']
    )
  end

  def seed_manifest(package_name:, normalized_package_name:)
    database.execute(
      <<~SQL,
        INSERT INTO package_manifests(
          repository_scan_id, ecosystem, path, package_name, normalized_package_name, confidence, parse_status,
          parser_version, parsed_at
        )
        VALUES (1, 'npm', 'package.json', ?, ?, 'high', 'parsed', 'test', ?)
      SQL
      [package_name, normalized_package_name, '2026-05-23T12:00:00Z']
    )
  end

  def seed_pending_package
    database.execute(
      <<~SQL,
        INSERT INTO registry_packages(
          ecosystem, package_name, normalized_package_name, registry_url, status, updated_at
        )
        VALUES ('npm', 'tool', 'tool', 'https://www.npmjs.com/package/tool', 'pending', ?)
      SQL
      ['2026-05-23T12:00:00Z']
    )
  end

  def successful_result
    package = PolishOpenSourceRank::Contexts::Packages::Domain::RegistryPackage.new(
      ecosystem: 'npm',
      package_name: 'tool',
      registry_url: 'https://www.npmjs.com/package/tool',
      latest_version: '1.2.3'
    )
    snapshot = PolishOpenSourceRank::Contexts::Packages::Domain::RegistryPackageSnapshot.new(
      ecosystem: 'npm',
      package_name: 'tool',
      downloads_30d: 55,
      latest_version: '1.2.3'
    )
    PolishOpenSourceRank::Contexts::Packages::Domain::RegistryFetchResult.new(
      status: 'ok',
      package: package,
      snapshot: snapshot
    )
  end

  def registry_packages
    database.fetch_all('SELECT * FROM registry_packages ORDER BY ecosystem, normalized_package_name')
  end

  def registry_links
    database.fetch_all('SELECT * FROM registry_package_links ORDER BY id')
  end

  def registry_snapshots
    database.fetch_all('SELECT * FROM registry_package_snapshots ORDER BY ecosystem, normalized_package_name')
  end
end
