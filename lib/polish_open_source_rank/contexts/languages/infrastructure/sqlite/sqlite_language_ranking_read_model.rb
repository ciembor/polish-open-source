# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Languages
      module Infrastructure
        module SQLite
          class SQLiteLanguageRankingReadModel
            DEFAULT_LIMIT = 100
            MAX_LIMIT = 100
            REPOSITORY_KINDS = %w[user organization].freeze
            LANGUAGE_METRIC_EXPRESSIONS = {
              'repository_count' => 'COUNT(*)',
              'repository_stars_count' => 'SUM(stargazers_count)',
              'repository_stars_delta' => 'SUM(monthly_stars_delta)'
            }.freeze
            REPOSITORY_METRIC_EXPRESSIONS = {
              'repository_stars_count' => 'stargazers_count',
              'repository_stars_delta' => 'monthly_stars_delta'
            }.freeze

            def initialize(database)
              @database = database
            end

            def rankings(period_start:, limit: 10, repository_kind: nil)
              Domain::LanguageRankingMetric.keys.to_h do |metric|
                [metric.to_sym, ranked_languages(
                  period_start: period_start,
                  metric: metric,
                  limit: limit,
                  repository_kind: repository_kind
                )]
              end
            end

            def ranked_languages(period_start:, metric:, limit: DEFAULT_LIMIT, repository_kind: nil)
              validate_language_metric!(metric)
              validate_repository_kind!(repository_kind)

              database.fetch_all(
                ranked_languages_sql(metric, limit, repository_kind),
                language_bindings(period_start, repository_kind)
              )
            end

            def repository_rankings(language:, period_start:, limit: 10, repository_kind: nil)
              Domain::LanguageRepositoryRankingMetric.keys.to_h do |metric|
                [metric.to_sym, ranked_repositories(
                  language: language,
                  period_start: period_start,
                  metric: metric,
                  limit: limit,
                  repository_kind: repository_kind
                )]
              end
            end

            def ranked_repositories(language:, period_start:, metric:, limit: DEFAULT_LIMIT, repository_kind: nil)
              validate_repository_metric!(metric)
              validate_repository_kind!(repository_kind)

              database.fetch_all(
                ranked_repositories_sql(metric, limit, repository_kind),
                language_bindings(period_start, repository_kind) + [language]
              )
            end

            private

            attr_reader :database

            def ranked_languages_sql(metric, limit, repository_kind)
              <<~SQL
                WITH language_repositories AS (#{repository_union_sql(repository_kind)})
                SELECT language,
                       COUNT(*) AS repository_count,
                       SUM(stargazers_count) AS repository_stars_count,
                       SUM(monthly_stars_delta) AS repository_stars_delta
                FROM language_repositories
                GROUP BY language
                HAVING #{language_metric_filter_sql(metric)}
                ORDER BY #{language_metric_expression(metric)} DESC, language COLLATE NOCASE ASC
                LIMIT #{bounded_limit(limit)}
              SQL
            end

            def ranked_repositories_sql(metric, limit, repository_kind)
              <<~SQL
                WITH language_repositories AS (#{repository_union_sql(repository_kind)})
                SELECT language,
                       full_name,
                       repository_kind,
                       platform,
                       html_url,
                       description,
                       homepage,
                       stargazers_count AS repository_stars_count,
                       monthly_stars_delta AS repository_stars_delta
                FROM language_repositories
                WHERE lower(language) = lower(?)
                  #{repository_metric_filter_sql(metric)}
                ORDER BY #{repository_metric_expression(metric)} DESC, full_name COLLATE NOCASE ASC
                LIMIT #{bounded_limit(limit)}
              SQL
            end

            def repository_union_sql(repository_kind)
              return repository_select_sql(repository_kind) if repository_kind

              [repository_select_sql('user'), repository_select_sql('organization')].join("\nUNION ALL\n")
            end

            def repository_select_sql(repository_kind)
              repository_kind == 'organization' ? organization_repository_select_sql : user_repository_select_sql
            end

            def user_repository_select_sql
              <<~SQL
                SELECT repositories.language,
                       repositories.full_name,
                       'user' AS repository_kind,
                       repositories.platform,
                       repositories.html_url,
                       repositories.description,
                       repositories.homepage,
                       stats.stargazers_count,
                       stats.monthly_stars_delta
                FROM repository_monthly_stats stats
                INNER JOIN repositories
                  ON repositories.platform = stats.platform
                 AND repositories.github_id = stats.repository_github_id
                WHERE stats.period_start = ?
                  AND repositories.language IS NOT NULL
                  AND trim(repositories.language) != ''
              SQL
            end

            def organization_repository_select_sql
              <<~SQL
                SELECT repositories.language,
                       repositories.full_name,
                       'organization' AS repository_kind,
                       repositories.platform,
                       repositories.html_url,
                       repositories.description,
                       repositories.homepage,
                       stats.stargazers_count,
                       stats.monthly_stars_delta
                FROM organization_repository_monthly_stats stats
                INNER JOIN organization_repositories repositories
                  ON repositories.platform = stats.platform
                 AND repositories.github_id = stats.repository_github_id
                WHERE stats.period_start = ?
                  AND repositories.language IS NOT NULL
                  AND trim(repositories.language) != ''
              SQL
            end

            def language_bindings(period_start, repository_kind)
              repository_kind ? [period_start] : [period_start, period_start]
            end

            def language_metric_filter_sql(metric)
              expression = language_metric_expression(metric)
              return "#{expression} > 0" if metric.to_s == 'repository_stars_delta'

              "#{expression} IS NOT NULL"
            end

            def repository_metric_filter_sql(metric)
              return "AND #{repository_metric_expression(metric)} > 0" if metric.to_s == 'repository_stars_delta'

              ''
            end

            def language_metric_expression(metric)
              LANGUAGE_METRIC_EXPRESSIONS.fetch(metric.to_s)
            end

            def repository_metric_expression(metric)
              REPOSITORY_METRIC_EXPRESSIONS.fetch(metric.to_s)
            end

            def validate_language_metric!(metric)
              return if Domain::LanguageRankingMetric.supported_key?(metric)

              raise ArgumentError, "Unsupported language ranking metric: #{metric}"
            end

            def validate_repository_metric!(metric)
              return if Domain::LanguageRepositoryRankingMetric.supported_key?(metric)

              raise ArgumentError, "Unsupported language repository ranking metric: #{metric}"
            end

            def validate_repository_kind!(repository_kind)
              return if repository_kind.nil? || REPOSITORY_KINDS.include?(repository_kind)

              raise ArgumentError, "Unsupported language repository kind: #{repository_kind}"
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
