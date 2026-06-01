# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          # Freezes public badge payloads so badge requests never calculate ranks live.
          class SQLitePublishedBadgeMaterializer
            def initialize(database, badge_policy: Domain::BadgePolicy.new)
              @database = database
              @badge_policy = badge_policy
            end

            def materialize(period_start, timestamp:)
              publication = { period_start: period_start, timestamp: timestamp }
              database.execute('DELETE FROM published_badges WHERE period_start = ?', [period_start])
              insert_user_badges(publication)
              insert_organization_badges(publication)
              insert_repository_badges(publication)
            end

            private

            attr_reader :badge_policy, :database

            def insert_user_badges(publication)
              database.fetch_all(user_badge_sql, [publication.fetch(:period_start)] * 3).each do |row|
                insert_badge(row.merge(badge_kind: 'user'), publication.fetch(:timestamp))
              end
            end

            def insert_organization_badges(publication)
              database.fetch_all(organization_badge_sql, [publication.fetch(:period_start)] * 3).each do |row|
                insert_badge(row.merge(badge_kind: 'organization'), publication.fetch(:timestamp))
              end
            end

            def insert_repository_badges(publication)
              period_start = publication.fetch(:period_start)
              database.fetch_all(repository_badge_sql, [period_start, period_start]).each do |row|
                policy_badge = repository_badge_policy(row.fetch(:badge_kind)).call(row.fetch(:rank), row[:language])
                insert_badge(row.merge(label: policy_badge.fetch(:label), status: policy_badge.fetch(:status)),
                             publication.fetch(:timestamp))
              end
            end

            def repository_badge_policy(badge_kind)
              {
                'organization_repository' => method(:organization_repository_badge_payload)
              }.fetch(badge_kind, method(:repository_badge_payload))
            end

            def organization_repository_badge_payload(rank, language)
              badge_policy.organization_repository_badge(rank, language: language)
            end

            def repository_badge_payload(rank, language)
              badge_policy.repository_badge(rank, language: language)
            end

            def insert_badge(row, timestamp)
              database.execute(<<~SQL, badge_values(row, timestamp))
                INSERT INTO published_badges(
                  period_start, badge_kind, platform, subject_github_id, label, status, rank, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
              SQL
            end

            def badge_values(row, timestamp)
              [
                row.fetch(:period_start),
                row.fetch(:badge_kind),
                row.fetch(:platform),
                row.fetch(:subject_github_id),
                row.fetch(:label),
                row.fetch(:status),
                row[:rank],
                timestamp,
                timestamp
              ]
            end

            def user_badge_sql
              <<~SQL
                WITH country_ranks AS (
                  SELECT platform, user_github_id,
                         RANK() OVER (ORDER BY total_stars DESC, platform ASC, login COLLATE NOCASE ASC) AS rank
                  FROM user_monthly_stats
                  WHERE period_start = ? AND country = 'Poland'
                ),
                city_ranks AS (
                  SELECT platform, user_github_id,
                         RANK() OVER (
                           PARTITION BY city
                           ORDER BY total_stars DESC, platform ASC, login COLLATE NOCASE ASC
                         ) AS rank
                  FROM user_monthly_stats
                  WHERE period_start = ? AND city IS NOT NULL AND trim(city) != ''
                )
                SELECT stats.period_start, stats.platform, stats.user_github_id AS subject_github_id,
                       CASE
                         WHEN country_ranks.rank <= 100 THEN 'Polish Open Source'
                         WHEN city_ranks.rank <= 10 THEN stats.city || ' Elite'
                         WHEN city_ranks.rank <= 100 THEN stats.city || ' Top 100'
                         ELSE 'Polish Open Source'
                       END AS label,
                       CASE
                         WHEN country_ranks.rank <= 100 OR city_ranks.rank <= 100 THEN 'ranked'
                         ELSE 'outside_ranking'
                       END AS status,
                       CASE
                         WHEN country_ranks.rank <= 100 THEN country_ranks.rank
                         WHEN city_ranks.rank <= 100 THEN city_ranks.rank
                         ELSE NULL
                       END AS rank
                FROM user_monthly_stats stats
                LEFT JOIN country_ranks
                  ON country_ranks.platform = stats.platform
                 AND country_ranks.user_github_id = stats.user_github_id
                LEFT JOIN city_ranks
                  ON city_ranks.platform = stats.platform
                 AND city_ranks.user_github_id = stats.user_github_id
                WHERE stats.period_start = ?
              SQL
            end

            def organization_badge_sql
              <<~SQL
                WITH country_ranks AS (
                  SELECT platform, organization_github_id,
                         RANK() OVER (ORDER BY total_stars DESC, platform ASC, login COLLATE NOCASE ASC) AS rank
                  FROM organization_monthly_stats
                  WHERE period_start = ? AND country = 'Poland'
                ),
                city_ranks AS (
                  SELECT platform, organization_github_id,
                         RANK() OVER (
                           PARTITION BY city
                           ORDER BY total_stars DESC, platform ASC, login COLLATE NOCASE ASC
                         ) AS rank
                  FROM organization_monthly_stats
                  WHERE period_start = ? AND city IS NOT NULL AND trim(city) != ''
                )
                SELECT stats.period_start, stats.platform, stats.organization_github_id AS subject_github_id,
                       CASE
                         WHEN country_ranks.rank <= 100 THEN 'Polish Open Source Org'
                         WHEN city_ranks.rank <= 10 THEN stats.city || ' Org Elite'
                         WHEN city_ranks.rank <= 100 THEN stats.city || ' Org Top 100'
                         ELSE 'Polish Open Source Org'
                       END AS label,
                       CASE
                         WHEN country_ranks.rank <= 100 OR city_ranks.rank <= 100 THEN 'ranked'
                         ELSE 'outside_ranking'
                       END AS status,
                       CASE
                         WHEN country_ranks.rank <= 100 THEN country_ranks.rank
                         WHEN city_ranks.rank <= 100 THEN city_ranks.rank
                         ELSE NULL
                       END AS rank
                FROM organization_monthly_stats stats
                LEFT JOIN country_ranks
                  ON country_ranks.platform = stats.platform
                 AND country_ranks.organization_github_id = stats.organization_github_id
                LEFT JOIN city_ranks
                  ON city_ranks.platform = stats.platform
                 AND city_ranks.organization_github_id = stats.organization_github_id
                WHERE stats.period_start = ?
              SQL
            end

            def repository_badge_sql
              <<~SQL
                WITH repositories_for_badges AS (
                  SELECT 'repository' AS badge_kind, stats.period_start, stats.platform,
                         stats.repository_github_id AS subject_github_id, repositories.full_name,
                         repositories.language, stats.stargazers_count
                  FROM repository_monthly_stats stats
                  INNER JOIN repositories
                    ON repositories.platform = stats.platform
                   AND repositories.github_id = stats.repository_github_id
                  WHERE stats.period_start = ? AND stats.owner_country = 'Poland'
                  UNION ALL
                  SELECT 'organization_repository' AS badge_kind, stats.period_start, stats.platform,
                         stats.repository_github_id AS subject_github_id, repositories.full_name,
                         repositories.language, stats.stargazers_count
                  FROM organization_repository_monthly_stats stats
                  INNER JOIN organization_repositories repositories
                    ON repositories.platform = stats.platform
                   AND repositories.github_id = stats.repository_github_id
                  WHERE stats.period_start = ? AND stats.organization_country = 'Poland'
                ),
                ranked_language_repositories AS (
                  SELECT badge_kind, period_start, platform, subject_github_id, language,
                         RANK() OVER (
                           PARTITION BY lower(language)
                           ORDER BY stargazers_count DESC, platform ASC, full_name COLLATE NOCASE ASC
                         ) AS rank
                  FROM repositories_for_badges
                  WHERE language IS NOT NULL AND trim(language) != ''
                ),
                ranked_generic_repositories AS (
                  SELECT badge_kind, period_start, platform, subject_github_id, language,
                         RANK() OVER (
                           PARTITION BY badge_kind
                           ORDER BY stargazers_count DESC, platform ASC, full_name COLLATE NOCASE ASC
                         ) AS rank
                  FROM repositories_for_badges
                  WHERE language IS NULL OR trim(language) = ''
                )
                SELECT *
                FROM ranked_language_repositories
                UNION ALL
                SELECT *
                FROM ranked_generic_repositories
              SQL
            end
          end
        end
      end
    end
  end
end
