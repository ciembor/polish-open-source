# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          class SQLiteSnapshotRunRepository
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
              return if refresh_platforms.empty? && finished_without_retryable_candidates?(period)

              started_at = Time.now.utc.iso8601
              execute(<<~SQL, [period.start_date.to_s, period.end_date.to_s, started_at])
                INSERT INTO sync_runs(period_start, period_end, status, started_at)
                VALUES (?, ?, 'running', ?)
                ON CONFLICT(period_start) DO UPDATE SET
                  period_end = excluded.period_end,
                  status = 'running',
                  started_at = CASE
                    WHEN sync_runs.status = 'running' THEN sync_runs.started_at
                    ELSE excluded.started_at
                  END,
                  finished_at = NULL,
                  error = NULL
              SQL
              reset_failed_candidates(period, started_at)
              reset_incomplete_processed_candidates(period, started_at)
              reset_refresh_candidates(period, started_at, refresh_platforms)
              value('SELECT id FROM sync_runs WHERE period_start = ?', [period.start_date.to_s])
            end

            def finish(run_id)
              execute("UPDATE sync_runs SET status = 'finished', finished_at = ? WHERE id = ?",
                      [Time.now.utc.iso8601, run_id])
            end

            def fail(run_id, error)
              execute("UPDATE sync_runs SET status = 'failed', error = ? WHERE id = ?", [error, run_id])
            end

            def retryable_candidates?(period, platforms: nil)
              sql = RETRYABLE_CANDIDATES_SQL.dup
              params = [period.start_date.to_s]
              if platforms
                placeholders = (['?'] * platforms.length).join(', ')
                sql = sql.sub('WHERE period_start = ?', "WHERE period_start = ? AND platform IN (#{placeholders})")
                params.concat(platforms)
              end
              !value(sql, params).nil?
            end

            private

            attr_reader :database

            def finished_without_retryable_candidates?(period)
              !value(<<~SQL, [period.start_date.to_s]).nil?
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

            def reset_failed_candidates(period, updated_at)
              execute(<<~SQL, [updated_at, period.start_date.to_s])
                UPDATE candidate_users
                SET status = 'pending', error = NULL, updated_at = ?
                WHERE period_start = ? AND status = 'failed'
              SQL
            end

            def reset_incomplete_processed_candidates(period, updated_at)
              execute(<<~SQL, [updated_at, period.start_date.to_s])
                UPDATE candidate_users
                SET status = 'pending', error = NULL, updated_at = ?
                WHERE period_start = ?
                  AND #{INCOMPLETE_PROCESSED_CANDIDATE_CONDITION}
              SQL
            end

            def reset_refresh_candidates(period, updated_at, platforms)
              platforms.each do |platform|
                execute(<<~SQL, [updated_at, period.start_date.to_s, platform])
                  UPDATE candidate_users
                  SET status = 'pending', error = NULL, updated_at = ?
                  WHERE period_start = ? AND platform = ? AND status != 'pending'
                SQL
              end
            end

            def execute(sql, params)
              database.execute(sql, params)
            end

            def value(sql, params)
              database.get_first_value(sql, params)
            end
          end
        end
      end
    end
  end
end
