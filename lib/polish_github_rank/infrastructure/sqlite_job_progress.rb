# frozen_string_literal: true

module PolishGithubRank
  module Infrastructure
    class SQLiteJobProgress
      PLATFORM_ORDER = %w[github gitlab codeberg].freeze

      def initialize(database)
        @database = database
      end

      def call(now: Time.now.utc)
        run = current_run
        return { generated_at: now.iso8601, run: nil, platforms: [] } unless run

        {
          generated_at: now.iso8601,
          run: run.slice(:period_start, :period_end, :status, :started_at, :finished_at, :error),
          platforms: progress_platforms(run.fetch(:period_start)).map do |platform|
            platform_progress(run, platform, now)
          end
        }
      end

      private

      attr_reader :database

      def current_run
        fetch_all(<<~SQL).first
          SELECT period_start, period_end, status, started_at, finished_at, error
          FROM sync_runs
          ORDER BY datetime(started_at) DESC, period_start DESC
          LIMIT 1
        SQL
      end

      def progress_platforms(period_start)
        discovered = fetch_all(<<~SQL, [period_start, period_start, period_start]).map { |row| row.fetch(:platform) }
          SELECT platform FROM candidate_users WHERE period_start = ?
          UNION
          SELECT platform FROM user_monthly_stats WHERE period_start = ?
          UNION
          SELECT platform FROM repository_monthly_stats WHERE period_start = ?
        SQL
        PLATFORM_ORDER | discovered
      end

      def platform_progress(run, platform, now)
        checked_users = checked_users_count(run.fetch(:period_start), platform)
        checked_repositories = checked_repositories_count(run.fetch(:period_start), platform)
        {
          platform: platform,
          run_duration_seconds: run_duration_seconds(run, now),
          crawled_records_count: checked_users + checked_repositories,
          checked_users_count: checked_users,
          checked_repositories_count: checked_repositories,
          last_checked_user: last_checked_user(run.fetch(:period_start), platform),
          last_checked_repository: last_checked_repository(run.fetch(:period_start), platform)
        }
      end

      def run_duration_seconds(run, now)
        finished_at = run[:finished_at] ? Time.parse(run.fetch(:finished_at)) : now
        (finished_at - Time.parse(run.fetch(:started_at))).round
      end

      def checked_users_count(period_start, platform)
        fetch_value(<<~SQL, [period_start, platform]).to_i
          SELECT COUNT(*)
          FROM candidate_users
          WHERE period_start = ? AND platform = ? AND status != 'pending'
        SQL
      end

      def checked_repositories_count(period_start, platform)
        fetch_value(<<~SQL, [period_start, platform]).to_i
          SELECT COUNT(*)
          FROM repository_monthly_stats
          WHERE period_start = ? AND platform = ?
        SQL
      end

      def last_checked_user(period_start, platform)
        fetch_all(<<~SQL, [period_start, platform]).first
          SELECT login, status, updated_at AS checked_at
          FROM candidate_users
          WHERE period_start = ? AND platform = ? AND status != 'pending'
          ORDER BY datetime(updated_at) DESC, login COLLATE NOCASE ASC
          LIMIT 1
        SQL
      end

      def last_checked_repository(period_start, platform)
        fetch_all(<<~SQL, [period_start, platform]).first
          SELECT repositories.full_name, repository_monthly_stats.owner_login,
                 repository_monthly_stats.updated_at AS checked_at
          FROM repository_monthly_stats
          INNER JOIN repositories
            ON repositories.platform = repository_monthly_stats.platform
           AND repositories.github_id = repository_monthly_stats.repository_github_id
          WHERE repository_monthly_stats.period_start = ? AND repository_monthly_stats.platform = ?
          ORDER BY datetime(repository_monthly_stats.updated_at) DESC,
                   repositories.full_name COLLATE NOCASE ASC
          LIMIT 1
        SQL
      end

      def fetch_all(sql, params = [])
        database.execute(sql, params).map { |row| symbolize(row) }
      end

      def fetch_value(sql, params = [])
        database.get_first_value(sql, params)
      end

      def symbolize(row)
        row.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = value unless key.is_a?(Integer)
        end
      end
    end
  end
end
