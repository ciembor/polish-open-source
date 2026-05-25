# frozen_string_literal: true

module PolishOpenSourceRank
  module Interfaces
    module Composition
      class PackageRankingJobFactory
        def self.build(argv, configuration: Configuration.load, output: $stdout, crawl_jobs: nil)
          new(argv, configuration: configuration, output: output, crawl_jobs: crawl_jobs).build
        end

        def initialize(argv, configuration:, output:, crawl_jobs:)
          @argv = argv
          @configuration = configuration
          @output = output
          @crawl_jobs = crawl_jobs
        end

        def build
          validate_ecosystem!
          CLI::PackageRankingsCommand.new(
            argv: argv,
            job: job,
            output: output,
            crawl_jobs: crawl_jobs || crawl_job_repository
          )
        end

        private

        attr_reader :argv, :configuration, :crawl_jobs, :output

        def validate_ecosystem!
          return unless ecosystem_argument
          return if Contexts::Packages::Domain::Ecosystem.snapshot_supported?(ecosystem_argument)

          raise ArgumentError, "Unsupported package ecosystem: #{ecosystem_argument}"
        end

        def ecosystem_argument
          index = argv.index('--ecosystem') || argv.index('--platform')
          argv[index + 1] if index
        end

        def database
          @database ||= begin
            db = Shared::Infrastructure::SQLite::Database.open(configuration.database_path)
            Infrastructure::PlatformSchemaMigration.new(db, Infrastructure::SQLiteSchema.sql).bootstrap!
            db
          end
        end

        def job
          Contexts::Packages::Application::RunPackageSnapshot.new(
            run_repository: package_crawl_runs,
            repository_queue: package_repository_queue,
            manifest_scanner: manifest_scanner,
            registry_packages: registry_package_repository,
            registry_clients: registry_clients,
            work_events: job_work_events
          )
        end

        def manifest_scanner
          Contexts::Packages::Application::ScanRepositoryManifests.new(
            repository_queue: package_repository_queue,
            tree_gateway: package_tree_gateway,
            manifest_repository: package_manifest_repository,
            work_events: job_work_events
          )
        end

        def package_tree_gateway
          Contexts::Packages::Infrastructure::GitHub::GitHubRepositoryTreeGateway.new(github_client)
        end

        def github_client
          Infrastructure::GitHubClient.new(
            token: configuration.github_token,
            base_url: configuration.github_base_url,
            requests_per_minute: configuration.requests_per_minute,
            http: configuration.http_timeouts
          )
        end

        def registry_clients
          {
            'npm' => registry_client(registries::NpmRegistryClient, :npm),
            'rubygems' => registry_client(registries::RubyGemsRegistryClient, :rubygems),
            'crates' => registry_client(registries::CratesRegistryClient, :crates),
            'pypi' => registry_client(registries::PyPIRegistryClient, :pypi),
            'hex' => registry_client(registries::HexRegistryClient, :hex),
            'packagist' => registry_client(registries::PackagistRegistryClient, :packagist),
            'go' => registry_client(registries::GoRegistryClient, :go),
            'homebrew' => registry_client(registries::HomebrewRegistryClient, :homebrew),
            'nuget' => registry_client(registries::NuGetRegistryClient, :nuget),
            'maven' => registry_client(registries::MavenCentralRegistryClient, :maven),
            'terraform' => repository_signal_registry_client(:terraform),
            'conan' => repository_signal_registry_client(:conan),
            'vcpkg' => repository_signal_registry_client(:vcpkg),
            'swiftpm' => repository_signal_registry_client(:swiftpm),
            'pub' => repository_signal_registry_client(:pub),
            'apt' => repository_signal_registry_client(:apt),
            'rpm' => repository_signal_registry_client(:rpm),
            'nix' => repository_signal_registry_client(:nix)
          }
        end

        def registries
          Contexts::Packages::Infrastructure::Registries
        end

        def registry_client(klass, key)
          klass.new(
            requests_per_minute: configuration.package_registry_request_limits.fetch(key),
            http: configuration.http_timeouts
          )
        end

        def repository_signal_registry_client(key)
          registries::RepositorySignalRegistryClient.new(
            ecosystem: key,
            requests_per_minute: configuration.package_registry_request_limits.fetch(key),
            http: configuration.http_timeouts
          )
        end

        def package_crawl_runs
          @package_crawl_runs ||= Contexts::Packages::Infrastructure::SQLite::SQLitePackageCrawlRunRepository.new(database)
        end

        def package_repository_queue
          @package_repository_queue ||=
            Contexts::Packages::Infrastructure::SQLite::SQLitePackageRepositoryQueue.new(database)
        end

        def package_manifest_repository
          @package_manifest_repository ||=
            Contexts::Packages::Infrastructure::SQLite::SQLitePackageManifestRepository.new(
              database,
              work_events: job_work_events
            )
        end

        def registry_package_repository
          @registry_package_repository ||=
            Contexts::Packages::Infrastructure::SQLite::SQLiteRegistryPackageRepository.new(
              database,
              work_events: job_work_events
            )
        end

        def crawl_job_repository
          @crawl_job_repository ||= Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository.new(database)
        end

        def job_work_events
          @job_work_events ||= Contexts::Operations::Infrastructure::SQLite::SQLiteJobWorkEventRepository.new(database)
        end
      end
    end
  end
end
