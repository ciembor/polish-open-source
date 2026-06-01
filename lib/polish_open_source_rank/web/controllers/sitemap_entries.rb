# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      class SitemapEntries
        RANKING_SEGMENTS = [
          %w[users top],
          %w[users trending],
          %w[users active],
          %w[repositories top],
          %w[repositories trending],
          %w[organizations top],
          %w[organizations trending],
          %w[organizations members],
          %w[organization-repositories top],
          %w[organization-repositories trending]
        ].freeze

        def initialize(context, generated_on: Time.now.utc.strftime('%Y-%m-%d'))
          @context = context
          @generated_on = generated_on
        end

        def call
          locale_variants(base_paths).map do |path|
            { loc: full_url(app_path(path)), lastmod: generated_on }
          end
        end

        private

        attr_reader :context, :generated_on

        def base_paths
          static_paths + ranking_paths + language_paths + package_paths + edition_paths + profile_paths
        end

        def static_paths
          ['/', '/latest', '/organizations', '/about', '/editions', '/languages', '/packages']
        end

        def ranking_paths
          latest_paths = ['/latest/organizations'] + RANKING_SEGMENTS.map { |kind, metric| "/latest/#{kind}/#{metric}" }
          city_paths = city_slugs.flat_map do |slug|
            [
              "/locations/#{slug}",
              "/latest/locations/#{slug}",
              "/organizations/locations/#{slug}",
              "/latest/organizations/locations/#{slug}"
            ] + ranking_scope_paths("/latest/locations/#{slug}")
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

        def ranking_scope_paths(prefix)
          RANKING_SEGMENTS.map { |kind, metric| "#{prefix}/#{kind}/#{metric}" }
        end

        def package_paths
          latest_package_paths + edition_package_paths
        end

        def language_paths
          latest_language_paths + edition_language_paths
        end

        def latest_language_paths
          return [] unless latest_period

          language_scope_paths('/latest')
        end

        def edition_language_paths
          edition_period_slugs.flat_map { |period_slug| language_scope_paths("/#{period_slug}") }
        end

        def language_scope_paths(prefix)
          Contexts::Languages::Domain::LanguageRankingMetric.slugs.map { |metric| "#{prefix}/languages/#{metric}" }
        end

        def latest_package_paths
          return [] unless latest_period

          package_scope_paths('/latest', latest_period)
        end

        def edition_package_paths
          edition_period_slugs.flat_map do |period_slug|
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

        def profile_paths
          users = identity_paths(profile_read_model.public_user_identities, '/users')
          organizations = identity_paths(profile_read_model.public_organization_identities, '/organizations')
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
          edition_years.flat_map do |year|
            list_editions.call(year: year).editions.map { |edition| edition.fetch(:period_start)[0, 7] }
          end
        end

        def edition_years
          list_editions.call&.years || []
        end

        def city_slugs
          Contexts::Ranking::Domain::LocationCatalog.city_slugs
        end

        def locale_variants(paths)
          paths.flat_map { |path| [path, localized_public_path(path, locale: 'en')] }
        end

        def full_url(path)
          context.__send__(:full_url, path)
        end

        def app_path(path)
          context.__send__(:app_path, path)
        end

        def localized_public_path(path, locale:)
          context.__send__(:localized_public_path, path, locale: locale)
        end

        def latest_period
          context.__send__(:latest_period)
        end

        def package_ranking_read_model
          context.__send__(:packages).package_ranking_read_model
        end

        def profile_read_model
          context.__send__(:publication).profile_read_model
        end

        def show_rankings
          context.__send__(:publication).show_rankings
        end

        def list_editions
          context.__send__(:publication).list_editions
        end
      end
    end
  end
end
