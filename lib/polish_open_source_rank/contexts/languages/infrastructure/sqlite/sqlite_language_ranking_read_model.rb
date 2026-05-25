# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Languages
      module Infrastructure
        module SQLite
          class SQLiteLanguageRankingReadModel
            DEFAULT_LIMIT = 100
            MAX_LIMIT = 100
            METRIC_EXPRESSIONS = {
              'repository_count' => 'COUNT(*)',
              'repository_stars_count' => 'SUM(stargazers_count)',
              'repository_stars_delta' => 'SUM(monthly_stars_delta)'
            }.freeze

            def initialize(database)
              @database = database
            end

            def rankings(period_start:, limit: 10)
              Domain::LanguageRankingMetric.keys.to_h do |metric|
                [metric.to_sym, ranked_languages(period_start: period_start, metric: metric, limit: limit)]
              end
            end

            def ranked_languages(period_start:, metric:, limit: DEFAULT_LIMIT)
              validate_metric!(metric)

              database.fetch_all(ranked_languages_sql(metric, limit), [period_start, period_start])
            end

            private

            attr_reader :database

            def ranked_languages_sql(metric, limit)
              <<~SQL
                WITH language_repositories AS (
                  SELECT repositories.language,
                         repositories.full_name,
                         'user' AS repository_kind,
                         repositories.platform,
                         stats.stargazers_count,
                         stats.monthly_stars_delta
                  FROM repository_monthly_stats stats
                  INNER JOIN repositories
                    ON repositories.platform = stats.platform
                   AND repositories.github_id = stats.repository_github_id
                  WHERE stats.period_start = ?
                    AND repositories.language IS NOT NULL
                    AND trim(repositories.language) != ''
                  UNION ALL
                  SELECT repositories.language,
                         repositories.full_name,
                         'organization' AS repository_kind,
                         repositories.platform,
                         stats.stargazers_count,
                         stats.monthly_stars_delta
                  FROM organization_repository_monthly_stats stats
                  INNER JOIN organization_repositories repositories
                    ON repositories.platform = stats.platform
                   AND repositories.github_id = stats.repository_github_id
                  WHERE stats.period_start = ?
                    AND repositories.language IS NOT NULL
                    AND trim(repositories.language) != ''
                )
                SELECT language,
                       COUNT(*) AS repository_count,
                       SUM(stargazers_count) AS repository_stars_count,
                       SUM(monthly_stars_delta) AS repository_stars_delta,
                       MIN(full_name) AS sample_repository_full_name,
                       MIN(repository_kind) AS sample_repository_kind,
                       MIN(platform) AS sample_repository_platform
                FROM language_repositories
                GROUP BY language
                HAVING #{metric_filter_sql(metric)}
                ORDER BY #{metric_expression(metric)} DESC, language COLLATE NOCASE ASC
                LIMIT #{bounded_limit(limit)}
              SQL
            end

            def metric_filter_sql(metric)
              return "#{metric_expression(metric)} > 0" if metric.to_s == 'repository_stars_delta'

              "#{metric_expression(metric)} IS NOT NULL"
            end

            def metric_expression(metric)
              METRIC_EXPRESSIONS.fetch(metric.to_s)
            end

            def validate_metric!(metric)
              return if Domain::LanguageRankingMetric.supported_key?(metric)

              raise ArgumentError, "Unsupported language ranking metric: #{metric}"
            end

            def bounded_limit(limit)
              limit.to_i.clamp(1, MAX_LIMIT)
            end
          end
        end
      end
    end
  end
end
