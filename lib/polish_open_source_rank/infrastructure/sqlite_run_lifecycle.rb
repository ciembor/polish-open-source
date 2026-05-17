# frozen_string_literal: true

module PolishOpenSourceRank
  module Infrastructure
    class SQLiteRunLifecycle
      RETRYABLE_CANDIDATES_SQL = <<~SQL
        SELECT 1
        FROM candidate_users
        WHERE period_start = ? AND status IN ('pending', 'failed')
        LIMIT 1
      SQL

      def initialize(database)
        @database = database
      end

      def create(period)
        return if finished_without_retryable_candidates?(period)

        started_at = Time.now.utc.iso8601
        execute(<<~SQL, [period.start_date.to_s, period.end_date.to_s, started_at])
          INSERT INTO sync_runs(period_start, period_end, status, started_at)
          VALUES (?, ?, 'running', ?)
          ON CONFLICT(period_start) DO UPDATE SET
            period_end = excluded.period_end,
            status = 'running',
            started_at = excluded.started_at,
            finished_at = NULL,
            error = NULL
        SQL
        reset_failed_candidates(period, started_at)
        value('SELECT id FROM sync_runs WHERE period_start = ?', [period.start_date.to_s])
      end

      def finish(run_id)
        execute("UPDATE sync_runs SET status = 'finished', finished_at = ? WHERE id = ?",
                [Time.now.utc.iso8601, run_id])
      end

      def fail(run_id, error)
        execute("UPDATE sync_runs SET status = 'failed', error = ? WHERE id = ?", [error, run_id])
      end

      def retryable_candidates?(period)
        !value(RETRYABLE_CANDIDATES_SQL, [period.start_date.to_s]).nil?
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
                AND candidate_users.status IN ('pending', 'failed')
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

      def execute(sql, params)
        database.execute(sql, params)
      end

      def value(sql, params)
        database.get_first_value(sql, params)
      end
    end
  end
end
