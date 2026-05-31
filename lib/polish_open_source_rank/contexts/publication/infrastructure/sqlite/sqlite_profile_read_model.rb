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
              country_rank = user_country_rank(user.fetch(:platform), user.fetch(:github_id), public_period)
              city_rank = user_city_rank(user.fetch(:platform), user.fetch(:github_id), user[:city], public_period)
              badges = user_badges(country_rank: country_rank, city: user[:city], city_rank: city_rank)
              user.merge(
                elite_rank: country_rank,
                city_rank: city_rank,
                badges: badges,
                profile_badge: badges.first,
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

            def organization_profile(platform, login, period_start:)
              organization = fetch_organization_profile(platform, login, period_start)
              return unless organization

              ranking = organization_ranking(organization, period_start)
              organization.merge(
                elite_rank: ranking.fetch(:country_rank),
                city_rank: ranking.fetch(:city_rank),
                badges: [ranking.fetch(:badge)],
                profile_badge: ranking.fetch(:badge),
                repositories: top_organization_repositories(
                  organization.fetch(:platform),
                  organization.fetch(:github_id),
                  ranking.fetch(:period_start)
                )
              )
            end

            def organization_repository_profile(platform, owner, name, period_start:)
              repository = fetch_organization_repository_profile(platform, "#{owner}/#{name}", period_start)
              return unless repository

              public_period = repository[:period_start] || period_start
              repository.merge(
                elite_rank: organization_repository_rank(
                  repository.fetch(:platform),
                  repository.fetch(:github_id),
                  public_period
                ),
                polish_repo_badge: organization_repository_badge(
                  repository.fetch(:platform),
                  repository.fetch(:github_id),
                  public_period
                )
              )
            end

            private

            attr_reader :badge_policy, :database

            def fetch_user_profile(platform, login, period_start)
              database.fetch_all(<<~SQL, [period_start, platform, login]).first
                SELECT users.platform, users.github_id AS source_id, users.github_id, users.login, users.name, users.location_raw, users.city,
                       users.country, users.email, users.homepage, users.html_url, users.avatar_url,
                       stats.period_start, stats.public_repo_count, stats.total_stars, stats.monthly_stars_delta,
                       stats.merged_pull_requests_count
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

            def fetch_organization_profile(platform, login, period_start)
              database.fetch_all(<<~SQL, [period_start, platform, login]).first
                SELECT organizations.platform, organizations.github_id, organizations.login, organizations.name,
                       organizations.location_raw, organizations.city, organizations.country, organizations.email,
                       organizations.homepage, organizations.html_url, organizations.avatar_url, stats.period_start,
                       stats.public_repo_count, stats.total_stars, stats.monthly_stars_delta, stats.members_count
                FROM organizations
                LEFT JOIN organization_monthly_stats stats
                  ON stats.platform = organizations.platform
                 AND stats.organization_github_id = organizations.github_id
                 AND stats.period_start = ?
                WHERE organizations.platform = ? AND organizations.login = ?
                LIMIT 1
              SQL
            end

            def fetch_organization_repository_profile(platform, full_name, period_start)
              database.fetch_all(<<~SQL, [period_start, platform, full_name]).first
                SELECT repositories.platform, repositories.github_id, repositories.full_name, repositories.name,
                       repositories.description, repositories.html_url, repositories.homepage,
                       repositories.language, repositories.organization_github_id, repositories.organization_login,
                       organizations.name AS owner_name, organizations.html_url AS owner_html_url,
                       organizations.avatar_url AS owner_avatar_url,
                       stats.period_start, stats.organization_city, stats.organization_country,
                       stats.stargazers_count, stats.monthly_stars_delta
                FROM organization_repositories repositories
                INNER JOIN organizations
                  ON organizations.platform = repositories.platform
                 AND organizations.github_id = repositories.organization_github_id
                LEFT JOIN organization_repository_monthly_stats stats
                  ON stats.platform = repositories.platform
                 AND stats.repository_github_id = repositories.github_id
                 AND stats.period_start = ?
                WHERE repositories.platform = ? AND repositories.full_name = ?
                LIMIT 1
              SQL
            end

            def top_user_repositories(platform, user_id, period_start, limit: 6)
              return [] unless period_start

              top_user_repository_rows(platform, user_id, period_start, limit).map do |repository|
                repository.merge(
                  polish_repo_badge: repository_badge(
                    repository.fetch(:platform),
                    repository.fetch(:github_id),
                    period_start
                  )
                )
              end
            end

            def top_organization_repositories(platform, organization_id, period_start, limit: 6)
              return [] unless period_start

              top_organization_repository_rows(platform, organization_id, period_start, limit).map do |repository|
                repository.merge(
                  polish_repo_badge: organization_repository_badge(
                    repository.fetch(:platform),
                    repository.fetch(:github_id),
                    period_start
                  )
                )
              end
            end

            def top_user_repository_rows(platform, user_id, period_start, limit)
              database.fetch_all(<<~SQL, [period_start, platform, user_id])
                SELECT repositories.platform, repositories.github_id, repositories.full_name, repositories.name,
                       repositories.description,
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

            def top_organization_repository_rows(platform, organization_id, period_start, limit)
              database.fetch_all(<<~SQL, [period_start, platform, organization_id])
                SELECT repositories.platform, repositories.github_id, repositories.full_name, repositories.name,
                       repositories.description, repositories.html_url, repositories.homepage,
                       repositories.language, stats.stargazers_count, stats.monthly_stars_delta
                FROM organization_repository_monthly_stats stats
                INNER JOIN organization_repositories repositories
                  ON repositories.platform = stats.platform
                 AND repositories.github_id = stats.repository_github_id
                WHERE stats.period_start = ? AND stats.platform = ? AND stats.organization_github_id = ?
                ORDER BY stats.stargazers_count DESC, repositories.full_name COLLATE NOCASE ASC
                LIMIT #{bounded_limit(limit)}
              SQL
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

            def organization_country_rank(platform, organization_id, period_start)
              return unless period_start

              database.fetch_value(<<~SQL, [period_start, platform, organization_id])
                SELECT country_rank
                FROM (
                  SELECT stats.platform, stats.organization_github_id,
                         RANK() OVER (
                           ORDER BY stats.total_stars DESC, stats.platform ASC, stats.login COLLATE NOCASE ASC
                         ) AS country_rank
                  FROM organization_monthly_stats stats
                  WHERE stats.period_start = ? AND stats.country = 'Poland'
                )
                WHERE platform = ? AND organization_github_id = ?
              SQL
            end

            def organization_repository_rank(platform, repository_id, period_start)
              return unless period_start

              database.fetch_value(<<~SQL, [period_start, platform, repository_id])
                SELECT elite_rank
                FROM (
                  SELECT stats.platform, stats.repository_github_id,
                         RANK() OVER (
                           ORDER BY stats.stargazers_count DESC, stats.platform ASC,
                                    repositories.full_name COLLATE NOCASE ASC
                         ) AS elite_rank
                  FROM organization_repository_monthly_stats stats
                  INNER JOIN organization_repositories repositories
                    ON repositories.platform = stats.platform
                   AND repositories.github_id = stats.repository_github_id
                  WHERE stats.period_start = ? AND stats.organization_country = 'Poland'
                )
                WHERE platform = ? AND repository_github_id = ?
              SQL
            end

            def organization_repository_badge(platform, repository_id, period_start)
              rank = organization_repository_rank(platform, repository_id, period_start)
              badge_policy.organization_repository_badge(rank)
            end

            def organization_ranking(organization, fallback_period)
              public_period = organization[:period_start] || fallback_period
              country_rank = organization_country_rank(
                organization.fetch(:platform),
                organization.fetch(:github_id),
                public_period
              )
              city_rank = organization_city_rank(
                organization.fetch(:platform),
                organization.fetch(:github_id),
                organization[:city],
                public_period
              )
              {
                period_start: public_period,
                country_rank: country_rank,
                city_rank: city_rank,
                badge: badge_policy.organization_badge(country_rank, city: organization[:city], city_rank: city_rank)
              }
            end

            def organization_city_rank(platform, organization_id, city, period_start)
              return unless city && period_start

              database.fetch_value(<<~SQL, [period_start, city, platform, organization_id])
                SELECT city_rank
                FROM (
                  SELECT stats.platform, stats.organization_github_id,
                         RANK() OVER (
                           ORDER BY stats.total_stars DESC, stats.platform ASC, stats.login COLLATE NOCASE ASC
                         ) AS city_rank
                  FROM organization_monthly_stats stats
                  WHERE stats.period_start = ? AND stats.city = ?
                )
                WHERE platform = ? AND organization_github_id = ?
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

            def user_badges(country_rank:, city:, city_rank:)
              badge_policy.user_badges(country_rank: country_rank, city: city, city_rank: city_rank)
            end

            public

            def public_user_identities
              database.fetch_all(<<~SQL)
                SELECT platform, login
                FROM users
                ORDER BY platform ASC, login COLLATE NOCASE ASC
              SQL
            end

            def public_organization_identities
              database.fetch_all(<<~SQL)
                SELECT platform, login
                FROM organizations
                ORDER BY platform ASC, login COLLATE NOCASE ASC
              SQL
            end

            private

            def bounded_limit(limit)
              limit.to_i.clamp(1, REPOSITORY_LIMIT)
            end
          end
        end
      end
    end
  end
end
