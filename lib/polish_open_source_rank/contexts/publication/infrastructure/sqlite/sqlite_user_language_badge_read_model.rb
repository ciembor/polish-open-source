# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          # Reads the strongest language badge a public user earned in one period.
          class SQLiteUserLanguageBadgeReadModel
            ENABLED = false

            def initialize(database)
              @database = database
            end

            def top_badge(platform:, user_id:, period_start:)
              return unless ENABLED
              return unless period_start

              row = database.fetch_all(top_badge_sql, [period_start, platform, user_id]).first
              return unless row

              rank = row.fetch(:language_rank)
              {
                label: Domain::LanguageBadgeLabel.top_hundred(row.fetch(:language)),
                value: Domain::Rank.place(rank),
                status: 'ranked',
                rank: rank
              }
            end

            private

            attr_reader :database

            def top_badge_sql
              <<~SQL
                WITH ranked_language_users AS (
                  SELECT repositories.language,
                         stats.platform,
                         stats.owner_github_id,
                         stats.owner_login,
                         SUM(stats.stargazers_count) AS total_stars
                  FROM repository_monthly_stats stats
                  INNER JOIN repositories
                    ON repositories.platform = stats.platform
                   AND repositories.github_id = stats.repository_github_id
                  WHERE stats.period_start = ?
                    AND stats.stargazers_count >= 5
                    AND repositories.language IS NOT NULL
                    AND trim(repositories.language) != ''
                  GROUP BY repositories.language, stats.platform, stats.owner_github_id, stats.owner_login
                ),
                language_ranks AS (
                  SELECT language,
                         platform,
                         owner_github_id,
                         RANK() OVER (
                           PARTITION BY lower(language)
                           ORDER BY total_stars DESC, platform ASC, owner_login COLLATE NOCASE ASC
                         ) AS language_rank
                  FROM ranked_language_users
                )
                SELECT language, language_rank
                FROM language_ranks
                WHERE platform = ? AND owner_github_id = ? AND language_rank <= 100
                ORDER BY language_rank ASC, language COLLATE NOCASE ASC
                LIMIT 1
              SQL
            end
          end
        end
      end
    end
  end
end
