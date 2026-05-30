# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        class MonthlySourceMetricBackfill
          def initialize(store:, sources:, logger:, work_events:)
            @store = store
            @sources = sources
            @logger = logger
            @work_events = work_events
          end

          def call(period, scope: nil, refresh_user_merged_prs: false, refresh_organization_members: false)
            source_threads = MonthlySnapshotWorkflow::SourceThreads.start(sources, []) do |source, _refresh|
              refresh_source_metrics(
                period,
                source,
                scope: scope,
                refresh_user_merged_prs: refresh_user_merged_prs,
                refresh_organization_members: refresh_organization_members
              )
            end
            source_threads.join
            raise_if_every_source_failed(source_threads.errors)
          rescue StandardError
            source_threads&.stop
            raise
          end

          private

          attr_reader :logger, :sources, :store, :work_events

          def refresh_source_metrics(period, source, scope:, refresh_user_merged_prs:, refresh_organization_members:)
            errors = []
            if refresh_user_merged_prs && scope != :organizations
              errors << refresh_stage(source, 'refresh merged pull requests') do
                refresh_user_merged_prs_for_source(period, source)
              end
            end
            if refresh_organization_members && scope != :users
              errors << refresh_stage(source, 'refresh organization members') do
                refresh_organization_members_for_source(period, source)
              end
            end
            Thread.current[:error] = errors.compact.first
          end

          def refresh_stage(source, stage)
            yield
            nil
          rescue StandardError => e
            log(source, "#{stage} failed: #{e.class}: #{e.message}")
            e
          end

          def refresh_user_merged_prs_for_source(period, source)
            rows = store.user_stats_for_period(period, platform: source.platform)
            log(source, "refreshing merged pull requests for #{rows.length} users")
            rows.each do |row|
              record_work_event(
                period,
                stage: 'user_merged_pull_requests',
                unit_kind: 'user',
                platform: source.platform,
                subject_id: row.fetch(:source_id),
                subject_label: row.fetch(:login)
              ) do
                merged_pull_requests_count = source.merged_pull_requests_count(row, period)
                store.record_user_stats(row.merge(merged_pull_requests_count: merged_pull_requests_count))
              end
            end
          end

          def refresh_organization_members_for_source(period, source)
            return unless source.supports_organizations?

            rows = store.organization_stats_for_period(period, platform: source.platform)
            log(source, "refreshing organization members for #{rows.length} organizations")
            rows.each do |row|
              record_work_event(
                period,
                stage: 'organization_members',
                unit_kind: 'organization',
                platform: source.platform,
                subject_id: row.fetch(:source_id),
                subject_label: row.fetch(:login)
              ) do
                members_count = source.organization_members_count(row)
                store.record_organization_stats(row.merge(members_count: members_count))
              end
            end
          end

          def raise_if_every_source_failed(errors)
            raise errors.first if errors.length == sources.length
          end

          def log(source, message)
            logger.puts "[#{source.platform}] #{message}"
            logger.flush if logger.respond_to?(:flush)
          end

          def record_work_event(period, attributes, &)
            work_events.record_timed(
              period_start: period.start_date.to_s,
              job_kind: 'monthly',
              **attributes, &
            )
          end
        end
      end
    end
  end
end
