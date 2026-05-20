# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          class SQLiteProfileReadModel
            REPOSITORY_LIMIT = 100

            def initialize(database, badge_policy: Domain::BadgePolicy.new)
              @database = database
              @badge_policy = badge_policy
            end

            def user_profile(platform, login, period_start:)
              user = fetch_user_profile(platform, login, period_start)
              return unless user

              public_period = user[:period_start] || period_start
              user.merge(
                elite_rank: user_country_rank(user.fetch(:platform), user.fetch(:github_id), public_period),
                elite_badge: user_elite_badge(user.fetch(:platform), user.fetch(:github_id), public_period),
                repositories: top_user_repositories(user.fetch(:platform), user.fetch(:github_id), public_period)
              )
            end

            def repository_profile(platform, owner, name, period_start:)
              repository = fetch_repository_profile(platform, "#{owner}/#{name}", period_start)
              return unless repository

              public_period = repository[:period_start] || period_start
              repository.merge(
                elite_rank: repository_elite_rank(
                  repository.fetch(:platform),
                  repository.fetch(:github_id),
                  public_period
                ),
                polish_repo_badge: repository_badge(repository.fetch(:platform), repository.fetch(:github_id),
                                                    public_period)
              )
            end

            private

            attr_reader :badge_policy, :database

            def fetch_user_profile(platform, login, period_start)
              database.fetch_all(<<~SQL, [period_start, platform, login]).first
                SELECT users.platform, users.github_id, users.login, users.name, users.location_raw, users.city,
                       users.country, users.email, users.homepage, users.html_url, users.avatar_url,
                       stats.period_start, stats.public_repo_count, stats.total_stars, stats.monthly_stars_delta,
                       stats.public_activity_count
                FROM users
                LEFT JOIN user_monthly_stats stats
                  ON stats.platform = users.platform
                 AND stats.user_github_id = users.github_id
                 AND stats.period_start = ?
                WHERE users.platform = ? AND users.login = ?
                LIMIT 1
              SQL
            end

            def fetch_repository_profile(platform, full_name, period_start)
              database.fetch_all(<<~SQL, [period_start, platform, full_name]).first
                SELECT repositories.platform, repositories.github_id, repositories.full_name, repositories.name,
                       repositories.description, repositories.html_url, repositories.homepage, repositories.language,
                       repositories.owner_github_id, repositories.owner_login, users.name AS owner_name,
                       users.html_url AS owner_html_url, users.avatar_url AS owner_avatar_url,
                       stats.period_start, stats.owner_city, stats.owner_country,
                       stats.stargazers_count, stats.monthly_stars_delta
                FROM repositories
                INNER JOIN users
                  ON users.platform = repositories.platform
                 AND users.github_id = repositories.owner_github_id
                LEFT JOIN repository_monthly_stats stats
                  ON stats.platform = repositories.platform
                 AND stats.repository_github_id = repositories.github_id
                 AND stats.period_start = ?
                WHERE repositories.platform = ? AND repositories.full_name = ?
                LIMIT 1
              SQL
            end

            def top_user_repositories(platform, user_id, period_start, limit: 6)
              return [] unless period_start

              database.fetch_all(<<~SQL, [period_start, platform, user_id])
                SELECT repositories.platform, repositories.full_name, repositories.name, repositories.description,
                       repositories.html_url, repositories.homepage, repositories.language,
                       stats.stargazers_count, stats.monthly_stars_delta
                FROM repository_monthly_stats stats
                INNER JOIN repositories
                  ON repositories.platform = stats.platform
                 AND repositories.github_id = stats.repository_github_id
                WHERE stats.period_start = ? AND stats.platform = ? AND stats.owner_github_id = ?
                ORDER BY stats.stargazers_count DESC, repositories.full_name COLLATE NOCASE ASC
                LIMIT #{bounded_limit(limit)}
              SQL
            end

            def user_elite_badge(platform, user_id, period_start)
              rank = user_country_rank(platform, user_id, period_start)
              badge_policy.user_badge(rank, historical_top_ten: historical_user_top_ten?(platform, user_id))
            end

            def repository_elite_rank(platform, repository_id, period_start)
              return unless period_start

              database.fetch_value(<<~SQL, [period_start, platform, repository_id])
                SELECT elite_rank
                FROM (
                  SELECT stats.platform, stats.repository_github_id,
                         RANK() OVER (
                           ORDER BY stats.stargazers_count DESC, stats.platform ASC,
                                    repositories.full_name COLLATE NOCASE ASC
                         ) AS elite_rank
                  FROM repository_monthly_stats stats
                  INNER JOIN repositories
                    ON repositories.platform = stats.platform
                   AND repositories.github_id = stats.repository_github_id
                  WHERE stats.period_start = ? AND stats.owner_country = 'Poland'
                )
                WHERE platform = ? AND repository_github_id = ?
              SQL
            end

            def repository_badge(platform, repository_id, period_start)
              rank = repository_elite_rank(platform, repository_id, period_start)
              badge_policy.repository_badge(rank)
            end

            def historical_user_top_ten?(platform, user_id)
              !database.fetch_value(<<~SQL, [platform, user_id]).nil?
                SELECT 1
                FROM (
                  SELECT stats.period_start, stats.platform, stats.user_github_id,
                         RANK() OVER (
                           PARTITION BY stats.period_start
                           ORDER BY stats.total_stars DESC, stats.platform ASC, stats.login COLLATE NOCASE ASC
                         ) AS elite_rank
                  FROM user_monthly_stats stats
                  WHERE stats.country = 'Poland'
                )
                WHERE platform = ? AND user_github_id = ? AND elite_rank <= 10
                LIMIT 1
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

            def bounded_limit(limit)
              limit.to_i.clamp(1, REPOSITORY_LIMIT)
            end
          end
        end
      end
    end
  end
end
