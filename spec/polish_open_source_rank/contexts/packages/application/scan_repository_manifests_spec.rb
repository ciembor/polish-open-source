# frozen_string_literal: true

class FakePackageTreeGateway
  attr_reader :blob_calls

  def initialize
    @repositories = {}
    @trees = {}
    @blobs = {}
    @unavailable = []
    @blob_calls = []
  end

  def stub_repository(full_name, default_branch:)
    repositories[full_name] = { default_branch: default_branch }
  end

  def stub_tree(full_name, ref:, sha:, entries:, truncated: false)
    trees[[full_name, ref]] = PolishOpenSourceRank::Contexts::Packages::Domain::RepositoryTree.new(
      sha: sha,
      entries: entries,
      truncated: truncated
    )
  end

  def stub_blob(full_name, sha:, content:)
    blobs[[full_name, sha]] = content
  end

  def stub_unavailable(full_name)
    unavailable << full_name
  end

  def repository(full_name)
    raise_unavailable if unavailable.include?(full_name)

    repositories.fetch(full_name)
  end

  def tree(full_name, ref:)
    trees.fetch([full_name, ref])
  end

  def blob(full_name, sha:)
    blob_calls << { full_name: full_name, sha: sha }
    blobs.fetch([full_name, sha])
  end

  private

  attr_reader :blobs, :repositories, :trees, :unavailable

  def raise_unavailable
    raise PolishOpenSourceRank::Contexts::Packages::Application::RepositoryUnavailable, 'missing'
  end
end

class OneFailurePackageManifestRepository
  def initialize(delegate, error)
    @delegate = delegate
    @error = error
    @failed = false
  end

  def replace_detected(...)
    unless failed
      self.failed = true
      raise error
    end

    delegate.replace_detected(...)
  end

  private

  attr_accessor :failed
  attr_reader :delegate, :error
end

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Application::ScanRepositoryManifests do
  let(:clock) { -> { Time.utc(2026, 5, 23, 12, 0, 0) } }
  let(:tree_gateway) { FakePackageTreeGateway.new }
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }

  it 'fetches manifest blobs, stores detected manifests, and marks scans as scanned' do
    seed_scan(full_name: 'alice/app')
    stub_changed_repository

    result = use_case.call(period, limit: 10)

    expect(manifests.map { |manifest| manifest.slice(:ecosystem, :path, :package_name, :parse_status) }).to eq(
      [
        { ecosystem: 'npm', path: 'package.json', package_name: 'app', parse_status: 'parsed' },
        { ecosystem: 'rubygems', path: 'pkg/tool.gemspec', package_name: nil, parse_status: 'partial' }
      ]
    )
    expect(scan).to include(status: 'scanned', tree_sha: 'tree-sha', tree_truncated: 1, manifest_count: 2)
    expect(tree_gateway.blob_calls).to eq(
      [
        { full_name: 'alice/app', sha: 'package-sha' },
        { full_name: 'alice/app', sha: 'gemspec-sha' }
      ]
    )
    expect(result).to eq(scanned: 1, failed: 0, manifests: 2)
  end

  it 'filters manifests by ecosystem and skips unchanged trees without fetching blobs' do
    seed_scan(full_name: 'alice/app', tree_sha: 'tree-sha', manifest_count: 7)
    tree_gateway.stub_repository('alice/app', default_branch: 'main')
    tree_gateway.stub_tree('alice/app', ref: 'main', sha: 'tree-sha', entries: [{ path: 'package.json', sha: 'sha' }])

    use_case.call(period, ecosystem: 'npm', limit: 10)

    expect(manifests).to be_empty
    expect(scan).to include(status: 'scanned', manifest_count: 7)
    expect(tree_gateway.blob_calls).to be_empty
  end

  it 'reparses unchanged repositories selected because they have outdated failed manifests' do
    seed_scan(full_name: 'alice/app', tree_sha: 'tree-sha', manifest_count: 1)
    tree_gateway.stub_repository('alice/app', default_branch: 'main')
    tree_gateway.stub_tree('alice/app', ref: 'main', sha: 'tree-sha', entries: [{ path: 'package.json', sha: 'sha' }])
    tree_gateway.stub_blob('alice/app', sha: 'sha', content: '{"workspaces":["packages/*"]}')
    seed_manifest(
      scan.fetch(:id),
      ecosystem: 'npm',
      parse_status: 'failed',
      parser_version: 'manifest-parser-v1'
    )

    use_case.call(period, ecosystem: 'npm', limit: 10)

    expect(manifests).to contain_exactly(include(ecosystem: 'npm', parse_status: 'partial'))
    expect(tree_gateway.blob_calls).to eq([{ full_name: 'alice/app', sha: 'sha' }])
  end

  it 'marks unavailable repositories without retrying them as transient failures' do
    seed_scan(full_name: 'alice/missing')
    tree_gateway.stub_unavailable('alice/missing')

    result = use_case.call(period, limit: 10)

    expect(scan).to include(status: 'unavailable', error: 'missing', checked_at: '2026-05-23T12:00:00Z')
    expect(result).to eq(scanned: 0, failed: 1, manifests: 0)
  end

  it 'marks transient SQLite persistence failures as retryable and continues later scans' do
    seed_scan(full_name: 'alice/locked', source_id: 1)
    seed_scan(full_name: 'alice/app', source_id: 2)
    stub_changed_repository(full_name: 'alice/locked')
    stub_changed_repository(full_name: 'alice/app')
    failure = PolishOpenSourceRank::Contexts::Packages::Application::RetryableRepositoryScanFailure.new(
      'Retryable SQLite persistence failure: SQLite3::BusyException: database is locked'
    )
    repository = OneFailurePackageManifestRepository.new(manifest_repository, failure)

    result = described_class.new(
      repository_queue: repository_queue,
      tree_gateway: tree_gateway,
      manifest_repository: repository
    ).call(period, limit: 10)

    expect(scan_by_name('alice/locked')).to include(
      status: 'failed',
      error: 'Retryable SQLite persistence failure: SQLite3::BusyException: database is locked'
    )
    expect(scan_by_name('alice/app')).to include(status: 'scanned')
    expect(result).to eq(scanned: 1, failed: 1, manifests: 2)
  end

  it 'stores parser failures without aborting the repository scan' do
    seed_scan(full_name: 'alice/broken')
    tree_gateway.stub_repository('alice/broken', default_branch: 'main')
    tree_gateway.stub_tree(
      'alice/broken',
      ref: 'main',
      sha: 'broken-tree-sha',
      entries: [{ path: 'package.json', sha: 'broken-package-sha' }]
    )
    tree_gateway.stub_blob('alice/broken', sha: 'broken-package-sha', content: '{broken')

    use_case.call(period, limit: 10)

    expect(manifests.first).to include(
      ecosystem: 'npm',
      path: 'package.json',
      package_name: nil,
      parse_status: 'failed'
    )
    expect(scan).to include(status: 'scanned', tree_sha: 'broken-tree-sha', manifest_count: 1)
  end

  it 'replaces manifests that already have registry package links' do
    seed_scan(full_name: 'alice/app')
    stub_changed_repository
    use_case.call(period, limit: 10)
    seed_registry_package_link(manifests.first.fetch(:id))
    tree_gateway.stub_tree(
      'alice/app',
      ref: 'main',
      sha: 'updated-tree-sha',
      truncated: false,
      entries: [{ path: 'package.json', sha: 'updated-package-sha' }]
    )
    tree_gateway.stub_blob('alice/app', sha: 'updated-package-sha', content: '{"name":"updated-app"}')

    use_case.call(period, limit: 10, refresh: true)

    expect(manifests.map { |manifest| manifest.slice(:package_name, :path) }).to eq(
      [{ package_name: 'updated-app', path: 'package.json' }]
    )
    expect(database.fetch_value('SELECT COUNT(*) FROM registry_package_links')).to eq(0)
  end

  def seed_scan(full_name:, source_id: 1, tree_sha: nil, manifest_count: 0)
    database.execute(
      <<~SQL,
        INSERT INTO package_repository_scans(
          period_start, repository_kind, platform, repository_source_id, full_name, tree_sha, manifest_count,
          status, updated_at
        )
        VALUES (?, 'user', 'github', ?, ?, ?, ?, 'pending', ?)
      SQL
      [period.start_date.to_s, source_id, full_name, tree_sha, manifest_count, '2026-05-23T11:00:00Z']
    )
  end

  def seed_registry_package_link(manifest_id)
    database.execute(
      <<~SQL,
        INSERT INTO registry_packages(
          ecosystem, package_name, normalized_package_name, registry_url, status, updated_at
        )
        VALUES ('npm', 'app', 'app', 'https://www.npmjs.com/package/app', 'ok', ?)
      SQL
      ['2026-05-23T11:30:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO registry_package_links(
          manifest_id, ecosystem, normalized_package_name, match_confidence, matched, checked_at
        )
        VALUES (?, 'npm', 'app', 'exact', 1, ?)
      SQL
      [manifest_id, '2026-05-23T11:30:00Z']
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

  def scan
    database.fetch_all('SELECT * FROM package_repository_scans').first
  end

  def scan_by_name(full_name)
    database.fetch_all('SELECT * FROM package_repository_scans WHERE full_name = ?', [full_name]).first
  end

  def manifests
    database.fetch_all('SELECT * FROM package_manifests ORDER BY ecosystem, path')
  end

  def database
    @database ||= PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'scan_manifests.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end

  def repository_queue
    @repository_queue ||= PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageRepositoryQueue
                          .new(database, clock: clock)
  end

  def manifest_repository
    @manifest_repository ||= PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageManifestRepository
                             .new(database, clock: clock)
  end

  def use_case
    @use_case ||= described_class.new(
      repository_queue: repository_queue,
      tree_gateway: tree_gateway,
      manifest_repository: manifest_repository
    )
  end

  def stub_changed_repository(full_name: 'alice/app')
    tree_gateway.stub_repository(full_name, default_branch: 'main')
    tree_gateway.stub_tree(full_name, ref: 'main', sha: 'tree-sha', truncated: true, entries: tree_entries)
    tree_gateway.stub_blob(full_name, sha: 'package-sha', content: '{"name":"app"}')
    tree_gateway.stub_blob(full_name, sha: 'gemspec-sha', content: 'Gem::Specification.new')
  end

  def tree_entries
    [
      { path: 'package.json', sha: 'package-sha' },
      { path: 'pkg/tool.gemspec', sha: 'gemspec-sha' },
      { path: 'README.md', sha: 'readme-sha' }
    ]
  end
end
