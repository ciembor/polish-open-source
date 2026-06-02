# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # Runs monthly snapshot stages for each source while hiding threading and batch processing details.
        class MonthlySourceSnapshotRunner
          BATCH_SIZE = 50

          def self.build(store:, sources:, classifier:, catalog:, logger:, work_events:)
            MonthlySourceSnapshotRunnerBuilder.new(
              store: store,
              sources: sources,
              classifier: classifier,
              catalog: catalog,
              logger: logger,
              work_events: work_events
            ).build
          end

          CandidateProcessors = Struct.new(:user, :organization, keyword_init: true)

          def initialize(store:, sources:, logger:, candidate_discovery:, candidate_processors:, store_mutex:)
            @store = store
            @sources = sources
            @logger = logger
            @candidate_discovery = candidate_discovery
            @candidate_processors = candidate_processors
            @store_mutex = store_mutex
          end

          def call(request, refresh_platforms:)
            source_threads = SourceThreads.start(sources, refresh_platforms) do |source, refresh|
              run_source_snapshot(request, source, refresh: refresh)
            end
            source_threads.join
            raise_if_every_source_failed(source_threads.errors)
          rescue StandardError
            source_threads&.stop
            raise
          end

          def source_platforms
            sources.map(&:platform)
          end

          def source_count
            sources.length
          end

          private

          attr_reader :candidate_discovery, :candidate_processors, :logger, :sources, :store, :store_mutex

          def run_source_snapshot(request, source, refresh:)
            errors = []
            errors.concat(run_user_source_snapshot(request, source, refresh: refresh)) if request.user_sources?
            if request.organization_sources?
              errors.concat(run_organization_source_snapshot(request, source, refresh: refresh))
            end
            Thread.current[:error] = errors.compact.first
          end

          def run_user_source_snapshot(request, source, refresh:)
            stages = [
              run_source_stage(source, 'process existing candidates') do
                process_source_candidates(request, source, refresh: refresh)
              end
            ]
            return stages if request.existing_only?

            stages + [
              run_source_stage(source, 'discover') { candidate_discovery.discover_users(request.period, source) },
              run_source_stage(source, 'process') { process_source_candidates(request, source, refresh: refresh) }
            ]
          end

          def run_organization_source_snapshot(request, source, refresh:)
            stages = [
              run_source_stage(source, 'process existing organizations') do
                process_source_organizations(request, source, refresh: refresh)
              end
            ]
            return stages if request.existing_only?

            stages + [
              run_source_stage(source, 'discover organizations') do
                candidate_discovery.discover_organizations(request.period, source)
              end,
              run_source_stage(source, 'process organizations') do
                process_source_organizations(request, source, refresh: refresh)
              end
            ]
          end

          def run_source_stage(source, stage)
            yield
            nil
          rescue StandardError => e
            log(source, "#{stage} failed: #{e.class}: #{e.message}")
            e
          end

          def process_source_candidates(request, source, refresh:)
            loop do
              candidates = pending_candidates(request.period, source)
              break if candidates.empty?

              log(source, "processing #{candidates.length} candidates")
              candidates.each do |candidate|
                candidate_processors.user.process(
                  request.period,
                  source,
                  candidate,
                  refresh: refresh,
                  use_snapshot_star_diff: request.use_snapshot_star_diff?
                )
              end
            end
            log(source, 'candidate processing finished')
          end

          def process_source_organizations(request, source, refresh:)
            return unless source.supports_organizations?

            loop do
              candidates = pending_organization_candidates(request.period, source)
              break if candidates.empty?

              log(source, "processing #{candidates.length} organizations")
              candidates.each do |candidate|
                candidate_processors.organization.process(
                  request.period,
                  source,
                  candidate,
                  refresh: refresh,
                  use_snapshot_star_diff: request.use_snapshot_star_diff?
                )
              end
            end
            log(source, 'organization processing finished')
          end

          def pending_candidates(period, source)
            with_store do
              store.pending_candidates(period, platform: source.platform, limit: BATCH_SIZE)
            end
          end

          def pending_organization_candidates(period, source)
            with_store do
              store.pending_organization_candidates(period, platform: source.platform, limit: BATCH_SIZE)
            end
          end

          def raise_if_every_source_failed(errors)
            raise errors.first if errors.length == source_count
          end

          def with_store(&)
            store_mutex.synchronize(&)
          end

          def log(source, message)
            logger.puts "[#{source.platform}] #{message}"
          end

          # Owns source worker lifecycle so interruption cleanup stays in one place.
          class SourceThreads
            def self.start(sources, refresh_platforms)
              new(
                sources.map do |source|
                  Thread.new { yield(source, refresh_platforms.include?(source.platform)) }
                end
              )
            end

            def initialize(threads)
              @threads = threads
            end

            def join
              threads.each(&:join)
            end

            def errors
              threads.filter_map { |thread| thread[:error] }
            end

            def stop
              threads.each { |thread| thread.kill if thread.alive? }
              threads.each(&:join)
            end

            private

            attr_reader :threads
          end
        end
      end
    end
  end
end
