# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    class Composition
      # Owns the public URL inventory so sitemap rendering does not reach into read models.
      class SitemapCatalog
        RANKING_SEGMENTS = [
          %w[users top],
          %w[users trending],
          %w[users active],
          %w[repositories top],
          %w[repositories trending],
          %w[organizations top],
          %w[organizations trending],
          %w[organizations active],
          %w[organization-repositories top],
          %w[organization-repositories trending]
        ].freeze
        PEOPLE_RANKING_SEGMENTS = [
          %w[users top],
          %w[users trending],
          %w[users active],
          %w[repositories top],
          %w[repositories trending]
        ].freeze
        ORGANIZATION_RANKING_SEGMENTS = [
          %w[organizations top],
          %w[organizations trending],
          %w[organizations active],
          %w[organization-repositories top],
          %w[organization-repositories trending]
        ].freeze
        STATIC_PATHS = [
          '/people',
          '/organizations',
          '/about',
          '/editions',
          '/languages',
          '/packages'
        ].freeze

        def initialize(publication_read_models:, package_ranking_read_model:, show_rankings:, list_editions:)
          @publication_read_models = publication_read_models
          @package_ranking_read_model = package_ranking_read_model
          @show_rankings = show_rankings
          @list_editions = list_editions
        end

        def paths(latest_period:)
          STATIC_PATHS + ranking_paths + language_paths(latest_period) + package_paths(latest_period) +
            edition_paths + profile_paths(latest_period)
        end

        private

        attr_reader :publication_read_models, :package_ranking_read_model, :show_rankings, :list_editions

        def ranking_paths
          latest_paths = latest_ranking_scope_paths
          city_paths = city_slugs.flat_map do |slug|
            [
              "/people/locations/#{slug}",
              "/organizations/locations/#{slug}"
            ] + latest_ranking_scope_paths(scope_slug: slug)
          end

          edition_period_slugs.each_with_object(latest_paths + city_paths) do |period_slug, paths|
            paths << "/#{period_slug}"
            paths << "/#{period_slug}/organizations"
            paths.concat(city_slugs.map { |slug| "/#{period_slug}/locations/#{slug}" })
            paths.concat(city_slugs.map { |slug| "/#{period_slug}/organizations/locations/#{slug}" })
            paths.concat(ranking_scope_paths("/#{period_slug}"))
            paths.concat(city_slugs.flat_map { |slug| ranking_scope_paths("/#{period_slug}/locations/#{slug}") })
          end
        end

        def latest_ranking_scope_paths(scope_slug: 'poland')
          people_prefix = scope_slug == 'poland' ? '/people' : "/people/locations/#{scope_slug}"
          organization_prefix = scope_slug == 'poland' ? '/organizations' : "/organizations/locations/#{scope_slug}"

          latest_people_ranking_scope_paths(people_prefix) +
            latest_organization_ranking_scope_paths(organization_prefix)
        end

        def latest_people_ranking_scope_paths(prefix)
          PEOPLE_RANKING_SEGMENTS.map { |kind, metric| "#{prefix}/#{kind}/#{metric}" }
        end

        def latest_organization_ranking_scope_paths(prefix)
          ORGANIZATION_RANKING_SEGMENTS.map do |kind, metric|
            suffix = kind == 'organization-repositories' ? "repositories/#{metric}" : metric
            "#{prefix}/#{suffix}"
          end
        end

        def ranking_scope_paths(prefix)
          RANKING_SEGMENTS.map { |kind, metric| "#{prefix}/#{kind}/#{metric}" }
        end

        def language_paths(latest_period)
          latest_paths = latest_period ? language_scope_paths('') : []
          latest_paths + edition_period_slugs.flat_map { |period_slug| language_scope_paths("/#{period_slug}") }
        end

        def language_scope_paths(prefix)
          Contexts::Languages::Domain::LanguageRankingMetric.slugs.map { |metric| "#{prefix}/languages/#{metric}" }
        end

        def package_paths(latest_period)
          latest_paths = latest_period ? package_scope_paths('', latest_period) : []
          latest_paths + edition_period_slugs.flat_map do |period_slug|
            package_scope_paths("/#{period_slug}", "#{period_slug}-01")
          end
        end

        def package_scope_paths(prefix, period)
          package_ranking_read_model
            .ecosystems(period_start: period)
            .select { |ecosystem| package_ranking_ecosystem?(ecosystem) }
            .flat_map { |ecosystem| package_ecosystem_paths(prefix, ecosystem) }
        end

        def package_ecosystem_paths(prefix, ecosystem)
          path = "#{prefix}/packages/#{ecosystem}"
          metric_paths = Contexts::Packages::Domain::PackageRankingMetric
                         .slugs(ecosystem: ecosystem)
                         .map { |metric| "#{path}/#{metric}" }
          [path] + metric_paths
        end

        def package_ranking_ecosystem?(ecosystem)
          Contexts::Packages::Domain::PackageRankingMetric.slugs(ecosystem: ecosystem).any?
        end

        def edition_paths
          edition_years.map { |year| "/editions/#{year}" }
        end

        def profile_paths(latest_period)
          users = identity_paths(publication_read_models.profile.public_user_identities, '/users')
          organizations = identity_paths(
            publication_read_models.profile.public_organization_identities,
            '/organizations'
          )
          return users + organizations unless latest_period

          ranking_page = show_rankings.call(scope: 'poland', period_start: latest_period)
          users + organizations + ranking_repository_paths(ranking_page)
        end

        def ranking_repository_paths(ranking_page)
          repository_paths(ranking_page.repository_rankings, '/repositories') +
            repository_paths(ranking_page.organization_repository_rankings, '/organization-repositories')
        end

        def identity_paths(rows, prefix)
          rows.map { |row| "#{prefix}/#{row.fetch(:platform)}/#{row.fetch(:login)}" }
        end

        def repository_paths(rankings, prefix)
          rankings.values.flatten.map do |row|
            platform = row.fetch(:platform, 'github')
            owner, name = row.fetch(:full_name).split('/', 2)
            "#{prefix}/#{platform}/#{owner}/#{name}"
          end
        end

        def edition_period_slugs
          @edition_period_slugs ||= edition_years.flat_map do |year|
            list_editions.call(year: year).editions.map { |edition| edition.fetch(:period_start)[0, 7] }
          end
        end

        def edition_years
          @edition_years ||= list_editions.call&.years || []
        end

        def city_slugs
          @city_slugs ||= Contexts::Ranking::Domain::LocationCatalog.city_slugs
        end
      end
    end
  end
end
