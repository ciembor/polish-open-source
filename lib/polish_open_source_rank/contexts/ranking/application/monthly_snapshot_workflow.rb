# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        module MonthlySnapshotWorkflow
          private

          def run_source_snapshots(period, refresh_platforms:)
            threads = sources.map do |source|
              Thread.new { run_source_snapshot(period, source, refresh: refresh_platforms.include?(source.platform)) }
            end
            threads.each(&:join)
            errors = threads.filter_map { |thread| thread[:error] }
            raise errors.first if errors.length == sources.length
          end

          def complete_run(period, run_id)
            return store.fail_run(run_id, 'Retryable candidates remain') if source_retryable_candidates?(period)
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
        end
      end
    end
  end
end
