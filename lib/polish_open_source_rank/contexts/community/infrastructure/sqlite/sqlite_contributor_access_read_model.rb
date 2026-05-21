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

            def access(platform, user_github_id, period_start:)
              period_start = effective_period_start(period_start)
              rank = user_country_rank(platform, user_github_id, period_start)
              city = user_city(platform, user_github_id, period_start)
              city_slug = city_slug_for(city)
              city_rank = city && user_city_rank(platform, user_github_id, city, period_start)
              access_role_keys = role_policy.role_keys(country_rank: rank, city_slug: city_slug, city_rank: city_rank)
              badge_role_key = role_policy.badge_role_key(rank)

              {
                country_rank: rank,
                city: city,
                city_slug: city_slug,
                city_rank: city_rank,
                role_keys: [*access_role_keys, badge_role_key].compact,
                access_role_keys: access_role_keys,
                badge_role_key: badge_role_key
              }
            end

            def discord_access(platform, user_github_id, period_start:)
              access(platform, user_github_id, period_start: period_start)
            end

            private

            attr_reader :catalog, :database, :role_policy

            def effective_period_start(period_start)
              period_start || latest_public_period
            end

            def latest_public_period
              database.dataset(:user_monthly_stats).select_map(:period_start).max
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
          end
        end
      end
    end
  end
end
