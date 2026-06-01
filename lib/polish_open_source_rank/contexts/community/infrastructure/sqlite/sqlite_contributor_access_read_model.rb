# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Infrastructure
        module SQLite
          class SQLiteContributorAccessReadModel
            def initialize(
              database,
              catalog: Contexts::Ranking::Domain::LocationCatalog,
              role_policy: Domain::DiscordRolePolicy.new
            )
              @database = database
              @catalog = catalog
              @role_policy = role_policy
            end

            def access(platform, source_id, period_start:)
              period_start = effective_period_start(period_start)
              rank = user_country_rank(platform, source_id, period_start)
              city = user_city(platform, source_id, period_start)
              city_slug = city_slug_for(city)
              city_rank = city && user_city_rank(platform, source_id, city, period_start)
              language_accesses = user_language_accesses(platform, source_id, period_start)
              access_payload(
                country_rank: rank,
                city: city,
                city_slug: city_slug,
                city_rank: city_rank,
                language_accesses: language_accesses,
                **resolved_roles(country_rank: rank, city_slug: city_slug, city_rank: city_rank,
                                 language_accesses: language_accesses)
              )
            end

            def discord_access(platform, source_id, period_start:)
              access(platform, source_id, period_start: period_start)
            end

            def published_languages(period_start:)
              period_start = effective_period_start(period_start)
              return [] unless period_start

              database.fetch_all(<<~SQL, [period_start]).map { |row| row.fetch(:language) }
                SELECT DISTINCT repositories.language
                FROM repository_monthly_stats stats
                INNER JOIN repositories
                  ON repositories.platform = stats.platform
                 AND repositories.github_id = stats.repository_github_id
                WHERE stats.period_start = ?
                  AND repositories.language IS NOT NULL
                  AND trim(repositories.language) != ''
                ORDER BY repositories.language COLLATE NOCASE ASC
              SQL
            end

            private

            attr_reader :catalog, :database, :role_policy

            def effective_period_start(period_start)
              period_start || latest_public_period
            end

            def latest_public_period
              database.fetch_value(<<~SQL)
                SELECT MAX(sync_runs.period_start)
                FROM sync_runs
                WHERE sync_runs.status = 'finished'
                  AND EXISTS (
                    SELECT 1
                    FROM user_monthly_stats user_stats
                    WHERE user_stats.period_start = sync_runs.period_start
                  )
              SQL
            end

            def user_country_rank(platform, user_id, period_start)
              return unless period_start

              database.fetch_value(<<~SQL, [period_start, platform, user_id])
                SELECT country_rank
                FROM (
                  SELECT stats.platform, stats.user_github_id,
                         RANK() OVER (
                           ORDER BY stats.total_stars DESC, stats.platform ASC, stats.login COLLATE NOCASE ASC
                         ) AS country_rank
                  FROM user_monthly_stats stats
                  WHERE stats.period_start = ? AND stats.country = 'Poland'
                )
                WHERE platform = ? AND user_github_id = ?
              SQL
            end

            def user_city(platform, user_id, period_start)
              return unless period_start

              database.dataset(:user_monthly_stats)
                      .where(period_start: period_start, platform: platform, user_github_id: user_id)
                      .select_map(:city)
                      .first
            end

            def user_city_rank(platform, user_id, city, period_start)
              return unless city && period_start

              database.fetch_value(<<~SQL, [period_start, city, platform, user_id])
                SELECT city_rank
                FROM (
                  SELECT stats.platform, stats.user_github_id,
                         RANK() OVER (
                           ORDER BY stats.total_stars DESC, stats.platform ASC, stats.login COLLATE NOCASE ASC
                         ) AS city_rank
                  FROM user_monthly_stats stats
                  WHERE stats.period_start = ? AND stats.city = ?
                )
                WHERE platform = ? AND user_github_id = ?
              SQL
            end

            def city_slug_for(city)
              catalog::CITIES.find { |candidate| candidate.fetch(:name) == city }&.fetch(:slug)
            end

            def user_language_accesses(platform, user_id, period_start)
              return [] unless period_start

              database.fetch_all(
                user_language_accesses_sql,
                user_language_access_bindings(period_start, platform, user_id)
              ).map { |row| language_access(row) }
            end

            def access_payload(**attributes)
              attributes
            end

            def resolved_roles(country_rank:, city_slug:, city_rank:, language_accesses:)
              access_role_keys = role_policy.role_keys(
                country_rank: country_rank,
                city_slug: city_slug,
                city_rank: city_rank,
                language_accesses: language_accesses
              )
              badge_role_key = role_policy.badge_role_key(country_rank)

              {
                role_keys: [*access_role_keys, badge_role_key].compact,
                access_role_keys: access_role_keys,
                badge_role_key: badge_role_key
              }
            end

            def user_language_access_bindings(period_start, platform, user_id)
              [period_start, platform, user_id, period_start, platform, platform, user_id]
            end

            def language_access(row)
              { language: row.fetch(:language), member: true, rank: row[:language_rank] }
            end

            def user_language_accesses_sql
              <<~SQL
                WITH user_languages AS (
                  SELECT repositories.language
                  FROM repository_monthly_stats stats
                  INNER JOIN repositories
                    ON repositories.platform = stats.platform
                   AND repositories.github_id = stats.repository_github_id
                  WHERE stats.period_start = ?
                    AND stats.platform = ?
                    AND stats.owner_github_id = ?
                    AND repositories.language IS NOT NULL
                    AND trim(repositories.language) != ''
                  GROUP BY repositories.language
                ),
                ranked_language_users AS (
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
                    AND stats.platform = ?
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
                SELECT user_languages.language,
                       language_ranks.language_rank
                FROM user_languages
                LEFT JOIN language_ranks
                  ON lower(language_ranks.language) = lower(user_languages.language)
                 AND language_ranks.platform = ?
                 AND language_ranks.owner_github_id = ?
                ORDER BY COALESCE(language_ranks.language_rank, 1000000),
                         user_languages.language COLLATE NOCASE ASC
              SQL
            end
          end
        end
      end
    end
  end
end
