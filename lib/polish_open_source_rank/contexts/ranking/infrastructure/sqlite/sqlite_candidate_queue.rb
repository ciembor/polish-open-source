# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          class SQLiteCandidateQueue
            SUPPORTED_PLATFORMS = %w[github gitlab codeberg].freeze
            PROCESSED_USER_SQL = <<~SQL
              SELECT 1
              FROM user_monthly_stats user_stats
              WHERE user_stats.period_start = ?
                AND user_stats.platform = ?
                AND user_stats.user_github_id = ?
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
            SQL

            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def record(period, login:, source_query:, platform: 'github', source_id: nil, github_id: nil)
              source_id ||= github_id
              database.execute(<<~SQL, [period.start_date.to_s, platform, source_id, login, source_query, timestamp])
                INSERT INTO candidate_users(period_start, platform, github_id, login, source_query, status, updated_at)
                VALUES (?, ?, ?, ?, ?, 'pending', ?)
                ON CONFLICT(period_start, platform, login) DO UPDATE SET
                  github_id = excluded.github_id,
                  source_query = CASE
                    WHEN instr(candidate_users.source_query, excluded.source_query) > 0
                    THEN candidate_users.source_query
                    ELSE candidate_users.source_query || ', ' || excluded.source_query
                  END,
                  updated_at = CASE
                    WHEN candidate_users.status = 'pending' THEN excluded.updated_at
                    ELSE candidate_users.updated_at
                  END
              SQL
            end

            def pending(period, limit: 100, platform: nil)
              platform_sql = 'AND platform = ?' if platform
              params = [period.start_date.to_s]
              params << platform if platform
              params << limit
              database.fetch_all(<<~SQL, params)
                SELECT platform, github_id, github_id AS source_id, login
                FROM candidate_users
                WHERE period_start = ? AND status = 'pending' #{platform_sql}
                ORDER BY platform ASC, login COLLATE NOCASE ASC
                LIMIT ?
              SQL
            end

            def mark(period, platform, login, status = nil, error = nil)
              platform, login, status, error = normalized_mark_arguments(platform, login, status, error)
              database.execute(<<~SQL, [status, error, timestamp, period.start_date.to_s, platform, login])
                UPDATE candidate_users
                SET status = ?, error = ?, updated_at = ?
                WHERE period_start = ? AND platform = ? AND login = ?
              SQL
            end

            def processed_user?(period, platform, github_id = nil)
              platform, github_id = normalized_user_identity(platform, github_id)
              database.fetch_value(PROCESSED_USER_SQL, [period.start_date.to_s, platform, github_id])
            end

            private

            attr_reader :clock, :database

            def normalized_mark_arguments(platform, login, status, error)
              return [platform, login, status, error] if SUPPORTED_PLATFORMS.include?(platform)

              ['github', platform, login, status]
            end

            def normalized_user_identity(platform, github_id)
              return [platform, github_id] if github_id

              ['github', platform]
            end

            def timestamp
              clock.call.iso8601
            end
          end
        end
      end
    end
  end
end
