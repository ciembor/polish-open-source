# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          # Resolves repository language rankings across user and organization repositories.
          module SQLiteRepositoryLanguageRankQueries
            private

            def repository_language(platform, repository_id)
              database.fetch_value(
                'SELECT language FROM repositories WHERE platform = ? AND github_id = ?',
                [platform, repository_id]
              )
            end

            def organization_repository_language(platform, repository_id)
              database.fetch_value(
                'SELECT language FROM organization_repositories WHERE platform = ? AND github_id = ?',
                [platform, repository_id]
              )
            end

            def repository_language_rank(platform, repository_id, period_start, language)
              return unless period_start

              database.fetch_value(repository_language_rank_sql, [period_start, language, period_start, language,
                                                                  platform, repository_id])
            end

            def repository_language_rank_sql
              <<~SQL
                SELECT language_rank
                FROM (
                  SELECT ranked_repositories.platform,
                         ranked_repositories.repository_github_id,
                         RANK() OVER (
                           ORDER BY ranked_repositories.stargazers_count DESC, ranked_repositories.platform ASC,
                                    ranked_repositories.full_name COLLATE NOCASE ASC
                         ) AS language_rank
                  FROM (
                    SELECT stats.platform, stats.repository_github_id, repositories.full_name, stats.stargazers_count
                    FROM repository_monthly_stats stats
                    INNER JOIN repositories
                      ON repositories.platform = stats.platform
                     AND repositories.github_id = stats.repository_github_id
                    WHERE stats.period_start = ?
                      AND stats.owner_country = 'Poland'
                      AND repositories.language = ?
                    UNION ALL
                    SELECT stats.platform, stats.repository_github_id, repositories.full_name, stats.stargazers_count
                    FROM organization_repository_monthly_stats stats
                    INNER JOIN organization_repositories repositories
                      ON repositories.platform = stats.platform
                     AND repositories.github_id = stats.repository_github_id
                    WHERE stats.period_start = ?
                      AND stats.organization_country = 'Poland'
                      AND repositories.language = ?
                  ) ranked_repositories
                )
                WHERE platform = ? AND repository_github_id = ?
              SQL
            end

            def present_language?(language)
              language && !language.empty?
            end
          end
        end
      end
    end
  end
end
