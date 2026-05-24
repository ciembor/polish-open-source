# frozen_string_literal: true

class FakeEndToEndPackageTreeGateway
  def repository(_full_name)
    { default_branch: 'main' }
  end

  def tree(_full_name, ref:)
    raise ArgumentError, ref unless ref == 'main'

    PolishOpenSourceRank::Contexts::Packages::Domain::RepositoryTree.new(
      sha: 'tree-sha',
      truncated: false,
      entries: [{ path: 'package.json', sha: 'package-blob-sha' }]
    )
  end

  def blob(_full_name, sha:)
    raise ArgumentError, sha unless sha == 'package-blob-sha'

    JSON.generate(name: 'polish-tool', repository: { url: 'https://github.com/alice/tool' }, license: 'MIT')
  end
end

class FakeEndToEndNpmRegistryClient
  def fetch(package_name)
    raise ArgumentError, package_name unless package_name == 'polish-tool'

    PolishOpenSourceRank::Contexts::Packages::Domain::RegistryFetchResult.new(
      status: 'ok',
      package: registry_package(package_name),
      snapshot: registry_snapshot(package_name)
    )
  end

  private

  def registry_package(package_name)
    PolishOpenSourceRank::Contexts::Packages::Domain::RegistryPackage.new(
      ecosystem: 'npm',
      package_name: package_name,
      registry_url: "https://www.npmjs.com/package/#{package_name}",
      repository_url: 'https://github.com/alice/tool',
      license: 'MIT',
      latest_version: '1.0.0'
    )
  end

  def registry_snapshot(package_name)
    PolishOpenSourceRank::Contexts::Packages::Domain::RegistryPackageSnapshot.new(
      ecosystem: 'npm',
      package_name: package_name,
      downloads_30d: 123,
      dependents_count: 7
    )
  end
end

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Application::RunPackageSnapshot do
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }

  it 'enqueues a repository, scans a manifest, snapshots registry data, and reads the ranking' do
    seed_repository

    run_package_snapshot.call(period, ecosystem: 'npm', limit: 10, refresh: false)

    expect(package_scan).to include(status: 'scanned', manifest_count: 1)
    expect(package_manifest).to include(package_name: 'polish-tool', parse_status: 'parsed')
    expect(ranking_row).to include(
      package_name: 'polish-tool',
      downloads_30d: 123,
      dependents_count: 7,
      repository_full_name: 'alice/tool'
    )
    expect(package_profile.fetch(:repositories).first).to include(repository_full_name: 'alice/tool')
  end

  def run_package_snapshot
    PolishOpenSourceRank::Contexts::Packages::Application::RunPackageSnapshot.new(
      run_repository: package_crawl_runs,
      repository_queue: repository_queue,
      manifest_scanner: manifest_scanner,
      registry_packages: registry_packages,
      registry_clients: { 'npm' => FakeEndToEndNpmRegistryClient.new }
    )
  end

  def manifest_scanner
    PolishOpenSourceRank::Contexts::Packages::Application::ScanRepositoryManifests.new(
      repository_queue: repository_queue,
      tree_gateway: FakeEndToEndPackageTreeGateway.new,
      manifest_repository: manifest_repository
    )
  end

  def seed_repository
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 1, 'alice', 'https://github.com/alice', timestamp]
    )
    database.execute(
      user_repository_sql,
      ['github', 10, 1, 'alice', 'tool', 'alice/tool', 'https://github.com/alice/tool', 0, 0, timestamp]
    )
    database.execute(
      user_repository_stats_sql,
      [period.start_date.to_s, 'github', 10, 1, 'alice', 'Warszawa', 'Poland', 50, 0, timestamp]
    )
  end

  def ranking_row
    package_rankings.ranked_packages(ecosystem: 'npm', period_start: period.start_date.to_s,
                                     metric: 'downloads_30d').first
  end

  def package_profile
    package_rankings.package_profile(ecosystem: 'npm', package_name: 'polish-tool',
                                     period_start: period.start_date.to_s)
  end

  def package_scan
    database.fetch_all('SELECT * FROM package_repository_scans').first
  end

  def package_manifest
    database.fetch_all('SELECT * FROM package_manifests').first
  end

  def package_crawl_runs
    PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageCrawlRunRepository.new(database)
  end

  def repository_queue
    @repository_queue ||= PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageRepositoryQueue
                          .new(database)
  end

  def manifest_repository
    PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageManifestRepository.new(database)
  end

  def registry_packages
    PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLiteRegistryPackageRepository.new(database)
  end

  def package_rankings
    PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageRankingReadModel.new(database)
  end

  def database
    @database ||= PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'package_snapshot_e2e.sqlite3')
    ).tap do |database|
      PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration
        .new(database, PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
        .bootstrap!
    end
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

  def timestamp
    '2026-05-24T10:00:00Z'
  end
end
