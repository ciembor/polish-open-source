# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          # Owns sync-run lifecycle writes while hiding the retryable-candidate reset rules.
          class SQLiteSnapshotRunRepository
            # Internal value object carrying the reopened run state across one transaction.
            RunContext = Struct.new(:period_start, :period_end, :started_at, :existing_run, keyword_init: true)
            # Applies one reopen-or-create transition to the sync_runs table.
            class RunContext
              def upsert_into(sync_runs)
                run_scope = sync_runs.where(period_start: period_start)

                if existing_run
                  run_scope.update(
                    period_end: period_end,
                    status: 'running',
                    started_at: reopened_started_at,
                    finished_at: nil,
                    error: nil
                  )
                else
                  sync_runs.insert(
                    period_start: period_start,
                    period_end: period_end,
                    status: 'running',
                    started_at: started_at
                  )
                end
              end

              private

              def reopened_started_at
                existing_run.fetch(:status) == 'running' ? existing_run.fetch(:started_at) : started_at
              end
            end
            INCOMPLETE_PROCESSED_CANDIDATE_CONDITION = <<~SQL
              status = 'processed'
              AND NOT EXISTS (
                SELECT 1
                FROM user_monthly_stats user_stats
                WHERE user_stats.period_start = candidate_users.period_start
                  AND user_stats.platform = candidate_users.platform
                  AND user_stats.user_github_id = candidate_users.github_id
                  AND (
                    user_stats.public_repo_count = 0
                    OR EXISTS (
                      SELECT 1
                      FROM repository_monthly_stats repository_stats
                      WHERE repository_stats.period_start = user_stats.period_start
                        AND repository_stats.platform = user_stats.platform
                        AND repository_stats.owner_github_id = user_stats.user_github_id
                    )
                  )
              )
            SQL
            RETRYABLE_CANDIDATES_SQL = <<~SQL.freeze
              SELECT 1
              FROM candidate_users
              WHERE period_start = ?
                AND (
                  status IN ('pending', 'failed')
                  OR #{INCOMPLETE_PROCESSED_CANDIDATE_CONDITION}
                )
              LIMIT 1
            SQL

            def initialize(database)
              @database = database
            end

            def create(period, refresh_platforms: [])
              period_start = period.start_date.to_s
              return if refresh_platforms.empty? && finished_without_retryable_candidates?(period_start)

              context = run_context(period_start, period.end_date.to_s)
              reopen_run(context, refresh_platforms)
              sync_run_id(period_start)
            end

            def finish(run_id)
              database.dataset(:sync_runs).where(id: run_id).update(status: 'finished', finished_at: timestamp)
            end

            def fail(run_id, error)
              database.dataset(:sync_runs).where(id: run_id).update(status: 'failed', error: error)
            end

            def retryable_candidates?(period, platforms: nil)
              return false if platforms&.empty?

              retryable_candidates(period.start_date.to_s, platforms: platforms).any?
            end

            private

            attr_reader :database

            def run_context(period_start, period_end)
              started_at = timestamp

              RunContext.new(
                period_start: period_start,
                period_end: period_end,
                started_at: started_at,
                existing_run: sync_run_for(period_start)
              )
            end

            def reopen_run(context, refresh_platforms)
              database.transaction do
                context.upsert_into(database.dataset(:sync_runs))
                reset_retryable_candidates(context.period_start, context.started_at, refresh_platforms)
              end
            end

            def sync_run_for(period_start)
              database.fetch_all('SELECT * FROM sync_runs WHERE period_start = ?', [period_start]).first
            end

            def sync_run_id(period_start)
              value('SELECT id FROM sync_runs WHERE period_start = ?', [period_start])
            end

            def finished_without_retryable_candidates?(period_start)
              value(<<~SQL, [period_start]) == 1
                SELECT 1
                FROM sync_runs
                WHERE period_start = ? AND status = 'finished'
                  AND NOT EXISTS (
                    SELECT 1
                    FROM candidate_users
                    WHERE candidate_users.period_start = sync_runs.period_start
                      AND (
                        candidate_users.status IN ('pending', 'failed')
                        OR #{INCOMPLETE_PROCESSED_CANDIDATE_CONDITION}
                      )
                  )
              SQL
            end

            def reset_retryable_candidates(period_start, updated_at, refresh_platforms)
              period_candidates = database.dataset(:candidate_users).where(period_start: period_start)
              period_candidates.where(status: 'failed').update(status: 'pending', error: nil, updated_at: updated_at)
              period_candidates
                .where(Sequel.lit(INCOMPLETE_PROCESSED_CANDIDATE_CONDITION))
                .update(status: 'pending', error: nil, updated_at: updated_at)
              reset_refresh_candidates(period_candidates, updated_at, refresh_platforms)
            end

            def reset_refresh_candidates(period_candidates, updated_at, platforms)
              platforms.each do |platform|
                period_candidates
                  .where(platform: platform)
                  .exclude(status: 'pending')
                  .update(status: 'pending', error: nil, updated_at: updated_at)
              end
            end

            def retryable_candidates(period_start, platforms:)
              candidates = database.dataset(:candidate_users).where(period_start: period_start)
              candidates = candidates.where(platform: platforms) if platforms
              candidates.where(retryable_candidate_condition)
            end

            def retryable_candidate_condition
              Sequel.|(
                { status: %w[pending failed] },
                Sequel.lit(INCOMPLETE_PROCESSED_CANDIDATE_CONDITION)
              )
            end

            def value(sql, params)
              database.fetch_value(sql, params)
            end

            def timestamp
              Time.now.utc.iso8601
            end
          end
        end
      end
    end
  end
end
