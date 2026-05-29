# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        module MonthlySnapshotWorkflow
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

          private

          def run_source_snapshots(period, refresh_platforms:)
            source_threads = SourceThreads.start(sources, refresh_platforms) do |source, refresh|
              run_source_snapshot(period, source, refresh: refresh)
            end
            source_threads.join
            raise_if_every_source_failed(source_threads.errors)
          rescue StandardError
            source_threads&.stop
            raise
          end

          def complete_run(period, run_id)
            if source_retryable_candidates?(period)
              retry_source_snapshots(period)
              return store.fail_run(run_id, 'Retryable candidates remain') if source_retryable_candidates?(period)
            end
            return if store.retryable_candidates?(period)

            store.prune_rankings(period)
            store.finish_run(run_id)
          end

          def source_retryable_candidates?(period)
            store.retryable_candidates?(
              period,
              platforms: sources.map(&:platform),
              candidate_types: active_candidate_types
            )
          end

          def active_candidate_types
            case @scope
            when :users then [:users]
            when :organizations then [:organizations]
            else %i[users organizations]
            end
          end

          def run_source_snapshot(period, source, refresh:)
            errors = []
            errors.concat(run_user_source_snapshot(period, source, refresh: refresh)) unless @scope == :organizations
            errors.concat(run_organization_source_snapshot(period, source, refresh: refresh)) unless @scope == :users
            Thread.current[:error] = errors.compact.first
          end

          def run_user_source_snapshot(period, source, refresh:)
            stages = [
              run_source_stage(source, 'process existing candidates') do
                process_source_candidates(period, source, refresh: refresh)
              end
            ]
            return stages if @existing_only

            stages + [
              run_source_stage(source, 'discover') { discover_source_candidates(period, source) },
              run_source_stage(source, 'process') { process_source_candidates(period, source, refresh: refresh) }
            ]
          end

          def run_organization_source_snapshot(period, source, refresh:)
            stages = [
              run_source_stage(source, 'process existing organizations') do
                process_source_organizations(period, source, refresh: refresh)
              end
            ]
            return stages if @existing_only

            stages + [
              run_source_stage(source, 'discover organizations') { discover_source_organizations(period, source) },
              run_source_stage(source, 'process organizations') do
                process_source_organizations(period, source, refresh: refresh)
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

          def retry_source_snapshots(period)
            original_existing_only = @existing_only
            @existing_only = true
            store.create_run(period, refresh_platforms: [])
            run_source_snapshots(period, refresh_platforms: [])
          ensure
            @existing_only = original_existing_only
          end

          def raise_if_every_source_failed(errors)
            raise errors.first if errors.length == sources.length
          end
        end
      end
    end
  end
end
