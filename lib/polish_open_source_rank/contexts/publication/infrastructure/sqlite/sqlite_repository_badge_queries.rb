# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          # Resolves repository badges from public repository rankings.
          module SQLiteRepositoryBadgeQueries
            include SQLiteRepositoryLanguageRankQueries

            private

            def repository_badge(platform, repository_id, period_start)
              published = published_badge(:repository, platform, repository_id, period_start)
              return published if published

              language = repository_language(platform, repository_id)
              rank = repository_rank(platform, repository_id, period_start, language)
              badge_policy.repository_badge(rank, language: language)
            end

            def organization_repository_badge(platform, repository_id, period_start)
              published = published_badge(:organization_repository, platform, repository_id, period_start)
              return published if published

              language = organization_repository_language(platform, repository_id)
              rank = organization_repository_badge_rank(platform, repository_id, period_start, language)
              badge_policy.organization_repository_badge(rank, language: language)
            end

            def published_badge(kind, platform, subject_id, period_start)
              published_badge_read_model.badge(
                kind: kind.to_s,
                platform: platform,
                subject_id: subject_id,
                period_start: period_start
              )
            end

            def repository_rank(platform, repository_id, period_start, language)
              rank = repository_elite_rank(platform, repository_id, period_start) unless present_language?(language)
              return rank if rank

              repository_language_rank(platform, repository_id, period_start, language)
            end

            def organization_repository_badge_rank(platform, repository_id, period_start, language)
              unless present_language?(language)
                return organization_repository_rank(platform, repository_id, period_start)
              end

              repository_language_rank(platform, repository_id, period_start, language)
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
          end
        end
      end
    end
  end
end
