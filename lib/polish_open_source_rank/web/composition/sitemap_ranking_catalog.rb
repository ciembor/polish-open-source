# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    class Composition
      # Combines independently owned ranking URL inventories.
      class SitemapRankingCatalog
        def initialize(catalogs:)
          @catalogs = catalogs
        end

        def paths(latest_period:, period_slugs:)
          catalogs.flat_map { |catalog| catalog.paths(latest_period: latest_period, period_slugs: period_slugs) }
        end

        private

        attr_reader :catalogs
      end

      # Generates public people, organization, and repository ranking URLs.
      class PublicRankingSitemapCatalog
        # Describes a public ranking route independently from its scope and period.
        Route = Data.define(:kind, :metric, :suffix)
        # Binds a ranking route to its public prefix, geographic scope, and snapshot.
        Scope = Data.define(:prefix, :slug, :period_start) do
          def people_prefix
            slug == 'poland' ? '/people' : "/people/locations/#{slug}"
          end

          def organization_prefix
            slug == 'poland' ? '/organizations' : "/organizations/locations/#{slug}"
          end

          def index_paths
            [people_prefix, organization_prefix]
          end

          def ranking_scopes
            [with(prefix: people_prefix), with(prefix: organization_prefix)]
          end
        end

        HISTORICAL_ROUTES = [
          %w[users top users/top],
          %w[users trending users/trending],
          %w[users active users/active],
          %w[repositories top repositories/top],
          %w[repositories trending repositories/trending],
          %w[organizations top organizations/top],
          %w[organizations trending organizations/trending],
          %w[organizations active organizations/active],
          %w[organization-repositories top organization-repositories/top],
          %w[organization-repositories trending organization-repositories/trending]
        ].map { |values| Route.new(*values) }.freeze
        LATEST_PEOPLE_ROUTES = HISTORICAL_ROUTES.first(5).freeze
        LATEST_ORGANIZATION_ROUTES = [
          %w[organizations top top],
          %w[organizations trending trending],
          %w[organizations active active],
          %w[organization-repositories top repositories/top],
          %w[organization-repositories trending repositories/trending]
        ].map { |values| Route.new(*values) }.freeze

        def paths(latest_period:, period_slugs:)
          latest_paths(latest_period) + period_slugs.flat_map { |slug| historical_paths(slug) }
        end

        private

        def latest_paths(period_start)
          latest_scope_paths(Scope.new(nil, 'poland', period_start)) +
            city_slugs.flat_map do |slug|
              scope = Scope.new(nil, slug, period_start)
              scope.index_paths + latest_scope_paths(scope)
            end
        end

        def latest_scope_paths(scope)
          people_scope, organization_scope = scope.ranking_scopes
          route_paths(people_scope, LATEST_PEOPLE_ROUTES) +
            route_paths(organization_scope, LATEST_ORGANIZATION_ROUTES)
        end

        def historical_paths(period_slug)
          prefix = "/#{period_slug}"
          period_start = "#{period_slug}-01"
          [prefix, "#{prefix}/organizations"] +
            historical_city_indexes(prefix) +
            route_paths(Scope.new(prefix, 'poland', period_start), HISTORICAL_ROUTES) +
            city_slugs.flat_map do |slug|
              route_paths(Scope.new("#{prefix}/locations/#{slug}", slug, period_start), HISTORICAL_ROUTES)
            end
        end

        def historical_city_indexes(prefix)
          city_slugs.flat_map do |slug|
            ["#{prefix}/locations/#{slug}", "#{prefix}/organizations/locations/#{slug}"]
          end
        end

        def route_paths(scope, routes)
          routes.map { |route| "#{scope.prefix}/#{route.suffix}" }
        end

        def city_slugs
          @city_slugs ||= Contexts::Ranking::Domain::LocationCatalog.city_slugs
        end
      end

      # Generates aggregate language ranking URLs.
      class LanguageRankingSitemapCatalog
        # Binds language ranking metrics to a public period prefix and snapshot.
        Period = Data.define(:prefix, :start) do
          def path(metric)
            "#{prefix}/languages/#{metric.slug}"
          end
        end

        def paths(latest_period:, period_slugs:)
          current_paths(latest_period) + period_slugs.flat_map { |slug| historical_paths(slug) }
        end

        private

        def current_paths(latest_period)
          latest_period ? period_paths(Period.new('', latest_period)) : []
        end

        def historical_paths(period_slug)
          period_paths(Period.new("/#{period_slug}", "#{period_slug}-01"))
        end

        def period_paths(period)
          Contexts::Languages::Domain::LanguageRankingMetric.all.flat_map do |metric|
            metric_paths(period, metric)
          end
        end

        def metric_paths(period, metric)
          period.path(metric)
        end
      end

      # Generates package ecosystem and package ranking URLs.
      class PackageRankingSitemapCatalog
        # Carries the public package prefix and its underlying snapshot.
        Period = Data.define(:prefix, :start) do
          def ecosystem(name)
            Ecosystem.new("#{prefix}/packages/#{name}", name, start)
          end
        end
        # Owns package metric URL generation for one ecosystem and snapshot.
        Ecosystem = Data.define(:path, :name, :period_start) do
          def paths
            [path] + Contexts::Packages::Domain::PackageRankingMetric.all(ecosystem: name).flat_map do |metric|
              metric_path(metric)
            end
          end

          private

          def metric_path(metric)
            "#{path}/#{metric.slug}"
          end
        end

        def initialize(package_ranking_read_model:)
          @package_ranking_read_model = package_ranking_read_model
        end

        def paths(latest_period:, period_slugs:)
          current_paths(latest_period) + period_slugs.flat_map { |slug| historical_paths(slug) }
        end

        private

        attr_reader :package_ranking_read_model

        def current_paths(latest_period)
          latest_period ? period_paths(Period.new('', latest_period)) : []
        end

        def historical_paths(period_slug)
          period_paths(Period.new("/#{period_slug}", "#{period_slug}-01"))
        end

        def period_paths(period)
          ecosystems(period).flat_map { |ecosystem| ecosystem_paths(period, ecosystem) }
        end

        def ecosystems(period)
          package_ranking_read_model
            .ecosystems(period_start: period.start)
            .select { |ecosystem| package_ranking_ecosystem?(ecosystem) }
        end

        def ecosystem_paths(period, ecosystem)
          period.ecosystem(ecosystem).paths
        end

        def package_ranking_ecosystem?(ecosystem)
          Contexts::Packages::Domain::PackageRankingMetric.slugs(ecosystem: ecosystem).any?
        end
      end
    end
  end
end
