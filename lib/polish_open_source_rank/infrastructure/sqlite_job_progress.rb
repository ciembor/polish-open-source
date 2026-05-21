# frozen_string_literal: true

module PolishOpenSourceRank
  module Infrastructure
    class SQLiteJobProgress
      PLATFORM_ORDER = %w[github gitlab codeberg].freeze
      RECENT_EVENTS_SQL = <<~SQL
        SELECT *
        FROM (
          SELECT platform, 'candidate' AS source, login AS subject, status AS detail, updated_at AS recorded_at
          FROM candidate_users
          WHERE period_start = ?
            AND status != 'pending'
          UNION ALL
          SELECT repository_monthly_stats.platform,
                 'repository' AS source,
                 repositories.full_name AS subject,
                 'stored' AS detail,
                 repository_monthly_stats.updated_at AS recorded_at
          FROM repository_monthly_stats
          INNER JOIN repositories
            ON repositories.platform = repository_monthly_stats.platform
           AND repositories.github_id = repository_monthly_stats.repository_github_id
          WHERE repository_monthly_stats.period_start = ?
          UNION ALL
          SELECT platform, 'api' AS source, path AS subject, 'HTTP ' || status AS detail, recorded_at
          FROM api_request_events
          WHERE recorded_at >= ?
        )
        WHERE recorded_at >= ?
        ORDER BY datetime(recorded_at) DESC, platform ASC, source ASC, subject COLLATE NOCASE ASC
        LIMIT 30
      SQL
      RECENT_ERRORS_SQL = <<~SQL
        SELECT *
        FROM (
          SELECT platform,
                 'candidate' AS source,
                 login AS subject,
                 COALESCE(error, status) AS detail,
                 updated_at AS recorded_at
          FROM candidate_users
          WHERE period_start = ?
            AND status = 'failed'
          UNION ALL
          SELECT platform, 'api' AS source, path AS subject, 'HTTP ' || status AS detail, recorded_at
          FROM api_request_events
          WHERE recorded_at >= ?
            AND status >= 400
        )
        ORDER BY datetime(recorded_at) DESC, platform ASC, source ASC, subject COLLATE NOCASE ASC
        LIMIT 30
      SQL

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
          end,
          progress_points: progress_points(run, now),
          request_points: request_points(run, now),
          recent_events: recent_events(run),
          recent_errors: recent_errors(run)
        }
      end

      private

      attr_reader :database

      def current_run
        sync_runs_dataset
          .select(:period_start, :period_end, :status, :started_at, :finished_at, :error)
          .order(Sequel.desc(Sequel.function(:datetime, :started_at)), Sequel.desc(:period_start))
          .first
      end

      def progress_platforms(period_start)
        discovered = candidate_users_dataset.where(period_start: period_start).select_map(:platform) +
                     user_monthly_stats_dataset.where(period_start: period_start).select_map(:platform) +
                     repository_monthly_stats_dataset.where(period_start: period_start).select_map(:platform)
        PLATFORM_ORDER | discovered
      end

      def platform_progress(run, platform, now)
        checked_candidates = checked_candidates_count(run.fetch(:period_start), platform)
        accepted_users = accepted_users_count(run.fetch(:period_start), platform)
        checked_repositories = checked_repositories_count(run.fetch(:period_start), platform)
        repository_owners = repository_owners_count(run.fetch(:period_start), platform)
        {
          platform: platform,
          run_duration_seconds: run_duration_seconds(run, now),
          crawled_records_count: checked_candidates + checked_repositories,
          **platform_counts(run, platform, checked_candidates, accepted_users, checked_repositories, repository_owners),
          last_checked_user: last_checked_user(run.fetch(:period_start), platform),
          last_checked_repository: last_checked_repository(run.fetch(:period_start), platform),
          last_api_request: last_api_request(run, platform)
        }
      end

      def platform_counts(run, platform, checked_candidates, accepted_users, checked_repositories, repository_owners)
        {
          total_candidates_count: total_candidates_count(run.fetch(:period_start), platform),
          checked_users_count: checked_candidates,
          checked_candidates_count: checked_candidates,
          accepted_users_count: accepted_users,
          checked_repositories_count: checked_repositories,
          repository_owners_count: repository_owners,
          zero_repository_users_count: accepted_users - repository_owners,
          pending_candidates_count: candidates_count(run.fetch(:period_start), platform, 'pending'),
          rejected_candidates_count: candidates_count(run.fetch(:period_start), platform, 'rejected'),
          missing_candidates_count: candidates_count(run.fetch(:period_start), platform, 'missing'),
          failed_candidates_count: candidates_count(run.fetch(:period_start), platform, 'failed'),
          current_run_checked_candidates_count: current_run_candidates_count(run, platform),
          current_run_accepted_users_count: current_run_user_stats_count(run, platform),
          current_run_repository_owners_count: current_run_repository_owners_count(run, platform),
          current_run_repositories_count: current_run_repository_stats_count(run, platform)
        }
      end

      def run_duration_seconds(run, now)
        finished_at = run[:finished_at] ? Time.parse(run.fetch(:finished_at)) : now
        (finished_at - Time.parse(run.fetch(:started_at))).round
      end

      def checked_candidates_count(period_start, platform)
        candidate_users_dataset
          .where(period_start: period_start, platform: platform)
          .exclude(status: 'pending')
          .count
      end

      def total_candidates_count(period_start, platform)
        candidate_users_dataset.where(period_start: period_start, platform: platform).count
      end

      def accepted_users_count(period_start, platform)
        user_monthly_stats_dataset.where(period_start: period_start, platform: platform).count
      end

      def checked_repositories_count(period_start, platform)
        repository_monthly_stats_dataset.where(period_start: period_start, platform: platform).count
      end

      def repository_owners_count(period_start, platform)
        repository_monthly_stats_dataset
          .where(period_start: period_start, platform: platform)
          .distinct
          .count(:owner_github_id)
      end

      def candidates_count(period_start, platform, status)
        candidate_users_dataset.where(period_start: period_start, platform: platform, status: status).count
      end

      def current_run_candidates_count(run, platform)
        fetch_value(<<~SQL, [run.fetch(:period_start), platform, run.fetch(:started_at), run_finished_at(run)]).to_i
          SELECT COUNT(*)
          FROM candidate_users
          WHERE period_start = ?
            AND platform = ?
            AND updated_at >= ?
            AND updated_at <= ?
            AND status != 'pending'
        SQL
      end

      def current_run_user_stats_count(run, platform)
        fetch_value(<<~SQL, [run.fetch(:period_start), platform, run.fetch(:started_at), run_finished_at(run)]).to_i
          SELECT COUNT(*)
          FROM user_monthly_stats
          WHERE period_start = ?
            AND platform = ?
            AND updated_at >= ?
            AND updated_at <= ?
        SQL
      end

      def current_run_repository_stats_count(run, platform)
        fetch_value(<<~SQL, [run.fetch(:period_start), platform, run.fetch(:started_at), run_finished_at(run)]).to_i
          SELECT COUNT(*)
          FROM repository_monthly_stats
          WHERE period_start = ?
            AND platform = ?
            AND updated_at >= ?
            AND updated_at <= ?
        SQL
      end

      def current_run_repository_owners_count(run, platform)
        fetch_value(<<~SQL, [run.fetch(:period_start), platform, run.fetch(:started_at), run_finished_at(run)]).to_i
          SELECT COUNT(DISTINCT owner_github_id)
          FROM repository_monthly_stats
          WHERE period_start = ?
            AND platform = ?
            AND updated_at >= ?
            AND updated_at <= ?
        SQL
      end

      def last_checked_user(period_start, platform)
        fetch_all(<<~SQL, [period_start, platform]).first
          SELECT candidate_users.login,
                 candidate_users.status,
                 COALESCE(user_monthly_stats.updated_at, candidate_users.updated_at) AS checked_at
          FROM candidate_users
          LEFT JOIN user_monthly_stats
            ON user_monthly_stats.period_start = candidate_users.period_start
           AND user_monthly_stats.platform = candidate_users.platform
           AND user_monthly_stats.user_github_id = candidate_users.github_id
          WHERE candidate_users.period_start = ?
            AND candidate_users.platform = ?
            AND candidate_users.status != 'pending'
          ORDER BY datetime(checked_at) DESC, candidate_users.login COLLATE NOCASE ASC
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

      def last_api_request(run, platform)
        api_request_events_dataset
          .where(platform: platform)
          .where(Sequel.lit('recorded_at >= ?', run.fetch(:started_at)))
          .select(:path, :status, :recorded_at)
          .order(Sequel.desc(Sequel.function(:datetime, :recorded_at)), Sequel.desc(:id))
          .first
      end

      def progress_points(run, now)
        rows = fetch_all(<<~SQL, run_window_params(run, now))
          SELECT platform, minute, SUM(users) AS users, SUM(repositories) AS repositories
          FROM (
            SELECT platform, substr(updated_at, 1, 16) || ':00Z' AS minute, COUNT(*) AS users, 0 AS repositories
            FROM user_monthly_stats
            WHERE period_start = ? AND updated_at >= ? AND updated_at <= ?
            GROUP BY platform, minute
            UNION ALL
            SELECT platform, substr(updated_at, 1, 16) || ':00Z' AS minute, 0 AS users, COUNT(*) AS repositories
            FROM repository_monthly_stats
            WHERE period_start = ? AND updated_at >= ? AND updated_at <= ?
            GROUP BY platform, minute
          )
          GROUP BY platform, minute
          ORDER BY platform, minute
        SQL
        cumulative_points(rows)
      end

      def run_window_params(run, now)
        finished_at = run_finished_at(run, now)
        [
          run.fetch(:period_start), run.fetch(:started_at), finished_at,
          run.fetch(:period_start), run.fetch(:started_at), finished_at
        ]
      end

      def request_points(run, now)
        finished_at = run_finished_at(run, now)
        fetch_all(<<~SQL, [run.fetch(:started_at), finished_at])
          SELECT platform, substr(recorded_at, 1, 16) || ':00Z' AS minute,
                 COUNT(*) AS requests_count,
                 SUM(CASE WHEN status >= 400 THEN 1 ELSE 0 END) AS error_count
          FROM api_request_events
          WHERE recorded_at >= ? AND recorded_at <= ?
          GROUP BY platform, minute
          ORDER BY platform, minute
        SQL
      end

      def recent_events(run)
        params = [run.fetch(:period_start), run.fetch(:period_start), run.fetch(:started_at), run.fetch(:started_at)]
        fetch_all(RECENT_EVENTS_SQL, params)
      end

      def recent_errors(run)
        fetch_all(RECENT_ERRORS_SQL, [run.fetch(:period_start), run.fetch(:started_at)])
      end

      def run_finished_at(run, now = Time.now.utc)
        run[:finished_at] || now.iso8601
      end

      def cumulative_points(rows)
        totals = Hash.new { |hash, platform| hash[platform] = { users: 0, repositories: 0 } }
        rows.map do |row|
          total = totals[row.fetch(:platform)]
          total[:users] += row.fetch(:users).to_i
          total[:repositories] += row.fetch(:repositories).to_i
          {
            platform: row.fetch(:platform),
            minute: row.fetch(:minute),
            checked_users_count: total.fetch(:users),
            checked_repositories_count: total.fetch(:repositories)
          }
        end
      end

      def fetch_all(sql, params = [])
        database.fetch_all(sql, params)
      end

      def fetch_value(sql, params = [])
        database.fetch_value(sql, params)
      end

      def sync_runs_dataset
        database.dataset(:sync_runs)
      end

      def candidate_users_dataset
        database.dataset(:candidate_users)
      end

      def user_monthly_stats_dataset
        database.dataset(:user_monthly_stats)
      end

      def repository_monthly_stats_dataset
        database.dataset(:repository_monthly_stats)
      end

      def api_request_events_dataset
        database.dataset(:api_request_events)
      end
    end
  end
end
