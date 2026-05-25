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

  it 'resolves repository-signal manifests with escaped registry lookup URLs' do
    seed_scan
    seed_manifest(ecosystem: 'terraform', path: 'main.tf', package_name: 'alice/terraform-aws-tool',
                  normalized_package_name: 'alice/terraform-aws-tool')

    repository.resolve_from_manifests(period, ecosystem: 'terraform', limit: 10)

    expect(registry_packages.first).to include(
      ecosystem: 'terraform',
      registry_url: 'https://registry.terraform.io/search/modules?q=alice%2Fterraform-aws-tool'
    )
    seed_manifest(ecosystem: 'apt', path: 'debian/control', package_name: 'polish apt',
                  normalized_package_name: 'polish apt')

    repository.resolve_from_manifests(period, ecosystem: 'apt', limit: 10)

    expect(registry_packages).to include(
      include(ecosystem: 'apt', registry_url: 'https://packages.debian.org/search?keywords=polish%20apt')
    )
  end

  it 'records successful snapshots and skips already snapshotted packages unless refreshed' do
    seed_pending_package

    repository.record_fetch_result(period, registry_packages.first, successful_result)

    expect(repository.packages_to_fetch(period, ecosystem: 'npm', limit: 10, refresh: false)).to be_empty
    expect(repository.packages_to_fetch(period, ecosystem: 'npm', limit: 10, refresh: true).length).to eq(1)
    expect(registry_packages.first).to include(status: 'active', latest_version: '1.2.3')
    expect(registry_snapshots.first).to include(downloads_30d: 55, downloads_7d: nil)
  end

  it 'rejects registry packages whose source repository points elsewhere' do
    seed_scan
    seed_manifest(ecosystem: 'packagist', package_name: 'symfony/polyfill-mbstring',
                  normalized_package_name: 'symfony/polyfill-mbstring')
    repository.resolve_from_manifests(period, ecosystem: 'packagist', limit: 10)
    result = successful_result(
      ecosystem: 'packagist',
      package_name: 'symfony/polyfill-mbstring',
      registry_url: 'https://packagist.org/packages/symfony/polyfill-mbstring',
      repository_url: 'https://github.com/symfony/polyfill'
    )

    repository.record_fetch_result(period, registry_packages.first, result)

    expect(registry_packages.first).to include(status: 'not_found', error: 'registry repository mismatch')
    expect(registry_links.first).to include(match_confidence: 'low', matched: 0)
    expect(registry_snapshots).to be_empty
  end

  it 'rejects placeholder PyPI and RubyGems package names' do
    seed_pending_package(ecosystem: 'rubygems', package_name: 'foo',
                         registry_url: 'https://rubygems.org/gems/foo')

    repository.record_fetch_result(period, registry_packages.first,
                                   successful_result(ecosystem: 'rubygems', package_name: 'foo',
                                                     registry_url: 'https://rubygems.org/gems/foo'))

    expect(registry_packages.first).to include(status: 'not_found', error: 'placeholder package name')
    expect(registry_snapshots).to be_empty
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

  it 'preserves package metadata when an optional metric fetch fails' do
    seed_pending_package
    package = PolishOpenSourceRank::Contexts::Packages::Domain::RegistryPackage.new(
      ecosystem: 'npm',
      package_name: 'tool',
      registry_url: 'https://www.npmjs.com/package/tool',
      latest_version: '1.2.3'
    )
    result = PolishOpenSourceRank::Contexts::Packages::Domain::RegistryFetchResult.new(
      status: 'rate_limited',
      package: package,
      error: 'downloads limited'
    )

    repository.record_fetch_result(period, registry_packages.first, result)

    expect(registry_packages.first).to include(status: 'active', latest_version: '1.2.3', error: nil)
    expect(registry_snapshots).to be_empty
  end

  it 'keeps manifest context when repository-signal registries do not return their own metadata' do
    seed_pending_package(
      ecosystem: 'terraform',
      package_name: 'alice/terraform-aws-tool',
      registry_url: 'https://registry.terraform.io/search/modules?q=alice%2Fterraform-aws-tool',
      repository_url: 'https://github.com/alice/terraform-aws-tool',
      license: 'MIT'
    )
    result = PolishOpenSourceRank::Contexts::Packages::Infrastructure::Registries::RepositorySignalRegistryClient
             .new(ecosystem: :terraform)
             .fetch('alice/terraform-aws-tool')

    repository.record_fetch_result(period, registry_packages.first, result)

    expect(registry_packages.first).to include(
      repository_url: 'https://github.com/alice/terraform-aws-tool',
      license: 'MIT'
    )
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

  def seed_manifest(package_name:, normalized_package_name:, ecosystem: 'npm', path: 'package.json')
    database.execute(
      <<~SQL,
        INSERT INTO package_manifests(
          repository_scan_id, ecosystem, path, package_name, normalized_package_name, confidence, parse_status,
          parser_version, parsed_at
        )
        VALUES (1, ?, ?, ?, ?, 'high', 'parsed', 'test', ?)
      SQL
      [ecosystem, path, package_name, normalized_package_name, '2026-05-23T12:00:00Z']
    )
  end

  def seed_pending_package(attributes = {})
    ecosystem = attributes.fetch(:ecosystem, 'npm')
    package_name = attributes.fetch(:package_name, 'tool')
    database.execute(
      <<~SQL,
        INSERT INTO registry_packages(
          ecosystem, package_name, normalized_package_name, registry_url, repository_url, license, status, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, 'pending', ?)
      SQL
      [
        ecosystem,
        package_name,
        package_name.downcase,
        attributes.fetch(:registry_url, 'https://www.npmjs.com/package/tool'),
        attributes[:repository_url],
        attributes[:license],
        '2026-05-23T12:00:00Z'
      ]
    )
  end

  def successful_result(attributes = {})
    ecosystem = attributes.fetch(:ecosystem, 'npm')
    package_name = attributes.fetch(:package_name, 'tool')
    package = PolishOpenSourceRank::Contexts::Packages::Domain::RegistryPackage.new(
      ecosystem: ecosystem,
      package_name: package_name,
      registry_url: attributes.fetch(:registry_url, 'https://www.npmjs.com/package/tool'),
      repository_url: attributes[:repository_url],
      latest_version: '1.2.3'
    )
    snapshot = PolishOpenSourceRank::Contexts::Packages::Domain::RegistryPackageSnapshot.new(
      ecosystem: ecosystem,
      package_name: package_name,
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
