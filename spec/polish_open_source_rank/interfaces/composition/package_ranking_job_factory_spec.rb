# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Interfaces::Composition::PackageRankingJobFactory do
  it 'builds the package rankings command from configuration and infrastructure adapters' do
    configuration = configuration_double
    database = instance_double(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database)
    crawl_jobs = instance_double(PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository)

    stub_database(configuration, database)
    stub_package_collaborators(database, crawl_jobs)

    command = described_class.build(%w[--period 2026-04], configuration: configuration, output: StringIO.new)

    expect(command).to be_a(PolishOpenSourceRank::Interfaces::CLI::PackageRankingsCommand)
    expect(PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository)
      .to have_received(:new).with(database)
  end

  it 'rejects unsupported ecosystems before building the command' do
    configuration = instance_double(PolishOpenSourceRank::Configuration)

    expect do
      described_class.build(%w[--ecosystem unknown], configuration: configuration, output: StringIO.new)
    end.to raise_error(ArgumentError, 'Unsupported package ecosystem: unknown')
  end

  def configuration_double
    instance_double(
      PolishOpenSourceRank::Configuration,
      database_path: 'db/test.sqlite3',
      github_token: 'token',
      github_base_url: 'https://api.github.test',
      requests_per_minute: 60,
      http_timeouts: { open_timeout: 5, read_timeout: 30, write_timeout: 30 },
      package_registry_request_limits: {
        npm: 30, rubygems: 20, crates: 10, pypi: 20, hex: 20, packagist: 20, go: 20, homebrew: 20,
        nuget: 20, maven: 20, terraform: 20, conan: 20, vcpkg: 20, swiftpm: 20, pub: 20
      }
    )
  end

  def stub_database(configuration, database)
    migration = instance_double(PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration, bootstrap!: nil)
    allow(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database)
      .to receive(:open).with(configuration.database_path).and_return(database)
    allow(PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration)
      .to receive(:new).with(database, PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql).and_return(migration)
  end

  def stub_package_collaborators(database, crawl_jobs)
    stub_sqlite_collaborators(database, crawl_jobs)
    stub_github_collaborators
    stub_registry_clients
  end

  def stub_sqlite_collaborators(database, crawl_jobs)
    stub_package_sqlite_collaborators(database)
    stub_operations_sqlite_collaborators(database, crawl_jobs)
  end

  def stub_package_sqlite_collaborators(database)
    allow(PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageCrawlRunRepository)
      .to receive(:new).with(database).and_return(double('package crawl runs'))
    allow(PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageRepositoryQueue)
      .to receive(:new).with(database).and_return(double('package repository queue'))
    allow(PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageManifestRepository)
      .to receive(:new).with(database, work_events: anything).and_return(double('package manifest repository'))
    allow(PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLiteRegistryPackageRepository)
      .to receive(:new).with(database, work_events: anything).and_return(double('registry package repository'))
  end

  def stub_operations_sqlite_collaborators(database, crawl_jobs)
    allow(PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository)
      .to receive(:new).with(database).and_return(crawl_jobs)
    allow(PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteJobWorkEventRepository)
      .to receive(:new).with(database).and_return(double('job work events'))
  end

  def stub_github_collaborators
    github_client = instance_double(PolishOpenSourceRank::Infrastructure::GitHubClient)
    allow(PolishOpenSourceRank::Infrastructure::GitHubClient).to receive(:new).and_return(github_client)
    allow(PolishOpenSourceRank::Contexts::Packages::Infrastructure::GitHub::GitHubRepositoryTreeGateway)
      .to receive(:new).with(github_client).and_return(double('package tree gateway'))
  end

  def stub_registry_clients
    registries = PolishOpenSourceRank::Contexts::Packages::Infrastructure::Registries
    [
      registries::NpmRegistryClient, registries::RubyGemsRegistryClient, registries::CratesRegistryClient,
      registries::PyPIRegistryClient, registries::HexRegistryClient, registries::PackagistRegistryClient,
      registries::GoRegistryClient, registries::HomebrewRegistryClient, registries::NuGetRegistryClient,
      registries::MavenCentralRegistryClient
    ].each do |klass|
      allow(klass).to receive(:new).and_return(instance_double(klass))
    end
    allow(registries::RepositorySignalRegistryClient)
      .to receive(:new).and_return(instance_double(registries::RepositorySignalRegistryClient))
  end
end
