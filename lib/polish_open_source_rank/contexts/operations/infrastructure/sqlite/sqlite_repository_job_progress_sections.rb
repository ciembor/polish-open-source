# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Infrastructure
        module SQLite
          class SQLiteRepositoryJobProgressSections
            MONTHLY_REPOSITORY_STAGES = [
              { label: 'user repositories', stage: 'user_repository', stats_table: :user_monthly_stats,
                repository_stats_table: :repository_monthly_stats },
              { label: 'organization repositories', stage: 'organization_repository',
                stats_table: :organization_monthly_stats,
                repository_stats_table: :organization_repository_monthly_stats }
            ].freeze
            MONTHLY_PLATFORM_ORDER = %w[github gitlab codeberg].freeze

            def initialize(database:, finished_sync_run:, section_builder:)
              @database = database
              @finished_sync_run = finished_sync_run
              @section_builder = section_builder
            end

            def call(period_start, now)
              MONTHLY_PLATFORM_ORDER.flat_map do |platform|
                MONTHLY_REPOSITORY_STAGES.filter_map do |stage|
                  section_attributes(stage, period_start, platform, now)
                end
              end
            end

            private

            attr_reader :database, :finished_sync_run, :section_builder

            def section_attributes(stage, period_start, platform, now)
              total = total_repositories(stage.fetch(:stats_table), period_start, platform)
              events = repository_event_counts(period_start, stage.fetch(:stage), platform)
              snapshot_count = snapshot_count(stage.fetch(:repository_stats_table), period_start, platform)
              return if total.zero? && snapshot_count.zero? && events.values.sum.zero?

              progress = counts(total, events, snapshot_count, period_start)
              section(repository_attributes(stage, period_start, platform, now, progress, events))
            end

            def repository_attributes(stage, period_start, platform, now, progress, events)
              {
                label: "#{stage.fetch(:label)} / #{platform}",
                period_start: period_start,
                job_kind: 'monthly',
                stage: stage.fetch(:stage),
                unit_kind: 'repository',
                platform: platform,
                total: progress.fetch(:total),
                done: progress.fetch(:done),
                pending: progress.fetch(:pending),
                failed: progress.fetch(:failed),
                skipped: 0,
                status_detail: repository_status_detail(events),
                now: now
              }
            end

            def total_repositories(stats_table, period_start, platform)
              database.dataset(stats_table).where(period_start: period_start,
                                                  platform: platform).sum(:public_repo_count).to_i
            end

            def snapshot_count(repository_stats_table, period_start, platform)
              database.dataset(repository_stats_table).where(period_start: period_start, platform: platform).count
            end

            def counts(total, events, snapshot_count, period_start)
              done = [events.fetch(:stored) + events.fetch(:skipped), snapshot_count].max
              failed = events.fetch(:failed)
              return { total: total, done: total, pending: 0, failed: 0 } if finished_sync_run.call(period_start)

              { total: total, done: done, pending: [total - done - failed, 0].max, failed: failed }
            end

            def repository_event_counts(period_start, stage, platform)
              grouped = database.dataset(:job_work_events).where(
                period_start: period_start,
                job_kind: 'monthly',
                stage: stage,
                unit_kind: 'repository',
                platform: platform
              ).group_and_count(:status).all
              grouped.each_with_object({ stored: 0, skipped: 0, failed: 0 }) do |row, result|
                status = row.fetch(:status)
                count = row.fetch(:count).to_i
                result[:failed] += count if status == 'failed'
                result[:skipped] += count if status == 'skipped'
                result[:stored] += count unless %w[failed skipped].include?(status)
              end
            end

            def repository_status_detail(events)
              "stored=#{events.fetch(:stored)}, skipped=#{events.fetch(:skipped)}, failed=#{events.fetch(:failed)}"
            end

            def section(attributes)
              section_builder.call(attributes)
            end
          end
        end
      end
    end
  end
end
