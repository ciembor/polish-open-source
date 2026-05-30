# frozen_string_literal: true

module PolishOpenSourceRank
  module Interfaces
    module Composition
      class PackageRankingJobFactory
        DIRECT_REGISTRY_CLIENTS = {
          'npm' => %i[NpmRegistryClient npm],
          'rubygems' => %i[RubyGemsRegistryClient rubygems],
          'crates' => %i[CratesRegistryClient crates],
          'pypi' => %i[PyPIRegistryClient pypi],
          'hex' => %i[HexRegistryClient hex],
          'packagist' => %i[PackagistRegistryClient packagist],
          'go' => %i[GoRegistryClient go],
          'homebrew' => %i[HomebrewRegistryClient homebrew],
          'nuget' => %i[NuGetRegistryClient nuget],
          'maven' => %i[MavenCentralRegistryClient maven]
        }.freeze
        REPOSITORY_SIGNAL_REGISTRIES = %i[
          terraform conan vcpkg swiftpm pub apt rpm nix cran cpan hackage clojars julia conda
        ].freeze

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
            crawl_jobs: crawl_jobs || crawl_job_repository,
            monthly_completion: monthly_completion,
            watchdog: { heartbeat: package_progress_heartbeat }
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
          direct_registry_clients.merge(repository_signal_registry_clients)
        end

        def direct_registry_clients
          DIRECT_REGISTRY_CLIENTS.transform_values do |class_name, key|
            registry_client(registries.const_get(class_name), key)
          end
        end

        def repository_signal_registry_clients
          REPOSITORY_SIGNAL_REGISTRIES.to_h { |key| [key.to_s, repository_signal_registry_client(key)] }
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

        def monthly_completion
          @monthly_completion ||= Contexts::Packages::Infrastructure::SQLite::SQLiteMonthlySnapshotCompletion.new(database)
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
          @job_work_events ||=
            Contexts::Operations::Infrastructure::SQLite::SQLiteJobWorkEventRepository.new(
              database,
              heartbeat: package_progress_heartbeat
            )
        end

        def package_progress_heartbeat
          @package_progress_heartbeat ||= Contexts::Operations::Application::ProgressHeartbeat.new
        end
      end
    end
  end
end
