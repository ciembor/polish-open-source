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

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Application::ScanRepositoryManifests do
  let(:clock) { -> { Time.utc(2026, 5, 23, 12, 0, 0) } }
  let(:tree_gateway) { FakePackageTreeGateway.new }
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }

  it 'fetches manifest blobs, stores detected manifests, and marks scans as scanned' do
    seed_scan(full_name: 'alice/app')
    stub_changed_repository

    use_case.call(period, limit: 10)

    expect(manifests.map { |manifest| manifest.slice(:ecosystem, :path, :parse_status) }).to eq(
      [
        { ecosystem: 'npm', path: 'package.json', parse_status: 'partial' },
        { ecosystem: 'rubygems', path: 'pkg/tool.gemspec', parse_status: 'partial' }
      ]
    )
    expect(scan).to include(status: 'scanned', tree_sha: 'tree-sha', tree_truncated: 1, manifest_count: 2)
    expect(tree_gateway.blob_calls).to eq(
      [
        { full_name: 'alice/app', sha: 'package-sha' },
        { full_name: 'alice/app', sha: 'gemspec-sha' }
      ]
    )
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

  it 'marks unavailable repositories as failed' do
    seed_scan(full_name: 'alice/missing')
    tree_gateway.stub_unavailable('alice/missing')

    use_case.call(period, limit: 10)

    expect(scan).to include(status: 'failed', error: 'missing')
  end

  def seed_scan(full_name:, tree_sha: nil, manifest_count: 0)
    database.execute(
      <<~SQL,
        INSERT INTO package_repository_scans(
          period_start, repository_kind, platform, repository_source_id, full_name, tree_sha, manifest_count,
          status, updated_at
        )
        VALUES (?, 'user', 'github', 1, ?, ?, ?, 'pending', ?)
      SQL
      [period.start_date.to_s, full_name, tree_sha, manifest_count, '2026-05-23T11:00:00Z']
    )
  end

  def scan
    database.fetch_all('SELECT * FROM package_repository_scans').first
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

  def stub_changed_repository
    tree_gateway.stub_repository('alice/app', default_branch: 'main')
    tree_gateway.stub_tree('alice/app', ref: 'main', sha: 'tree-sha', truncated: true, entries: tree_entries)
    tree_gateway.stub_blob('alice/app', sha: 'package-sha', content: '{"name":"app"}')
    tree_gateway.stub_blob('alice/app', sha: 'gemspec-sha', content: 'Gem::Specification.new')
  end

  def tree_entries
    [
      { path: 'package.json', sha: 'package-sha' },
      { path: 'pkg/tool.gemspec', sha: 'gemspec-sha' },
      { path: 'README.md', sha: 'readme-sha' }
    ]
  end
end
