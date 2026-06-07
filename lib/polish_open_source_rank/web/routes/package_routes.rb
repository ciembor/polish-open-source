# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      module PackageRoutes
        def self.registered(app)
          app.get('/packages') { render_package_index('latest') }
          app.get('/packages/:ecosystem') { render_package_ecosystem('latest', params.fetch('ecosystem')) }
          register_current_routes(app)
          register_latest_routes(app)
          register_period_routes(app)
        end

        class << self
          private

          def register_current_routes(app)
            app.get(current_package_repository_metric_route(app)) do |ecosystem, repository_kind, metric, page|
              render_package_ranking_detail(
                'latest',
                ecosystem,
                metric,
                repository_kind_slug: repository_kind,
                page: page
              )
            end
            app.get(current_package_metric_route(app)) do |ecosystem, metric, page|
              render_package_ranking_detail('latest', ecosystem, metric, page: page)
            end
          end

          def register_latest_routes(app)
            app.get('/latest/packages/:ecosystem') do
              redirect_canonical_public_path("/packages/#{params.fetch('ecosystem')}")
            end
            app.get(latest_package_repository_metric_route) do |ecosystem, repository_kind, metric|
              redirect_canonical_public_path("/packages/#{ecosystem}/#{repository_kind}/#{metric}")
            end
            app.get(latest_package_metric_route) do |ecosystem, metric|
              redirect_canonical_public_path("/packages/#{ecosystem}/#{metric}")
            end
          end

          def register_period_routes(app)
            app.get(%r{/(\d{4}-\d{2})/packages}) { |period_slug| render_package_index(period_slug) }
            app.get(%r{/(\d{4}-\d{2})/packages/([^/]+)}) do |period_slug, ecosystem|
              render_package_ecosystem(period_slug, ecosystem)
            end
            app.get(period_package_repository_metric_route(app)) do |period_slug, ecosystem, repository_kind, metric,
                                                                  page|
              render_package_ranking_detail(
                period_slug,
                ecosystem,
                metric,
                repository_kind_slug: repository_kind,
                page: page
              )
            end
            app.get(period_package_metric_route(app)) do |period_slug, ecosystem, metric, page|
              render_package_ranking_detail(period_slug, ecosystem, metric, page: page)
            end
          end

          def latest_package_metric_route
            Regexp.new("/latest/packages/([^/]+)/(#{package_metric_slugs})")
          end

          def latest_package_repository_metric_route
            Regexp.new("/latest/packages/([^/]+)/(#{repository_kind_slugs})/(#{package_metric_slugs})")
          end

          def current_package_metric_route(app)
            Regexp.new("/packages/([^/]+)/(#{package_metric_slugs})#{app::RANKING_PAGE_SEGMENT}")
          end

          def current_package_repository_metric_route(app)
            Regexp.new(
              "/packages/([^/]+)/(#{repository_kind_slugs})/(#{package_metric_slugs})#{app::RANKING_PAGE_SEGMENT}"
            )
          end

          def package_metric_slugs
            Contexts::Packages::Domain::PackageRankingMetric.slugs_pattern
          end

          def period_package_metric_route(app)
            Regexp.new(
              "/(\\d{4}-\\d{2})/packages/([^/]+)/(#{package_metric_slugs})#{app::RANKING_PAGE_SEGMENT}"
            )
          end

          def period_package_repository_metric_route(app)
            Regexp.new(
              "/(\\d{4}-\\d{2})/packages/([^/]+)/(#{repository_kind_slugs})/(#{package_metric_slugs})" \
              "#{app::RANKING_PAGE_SEGMENT}"
            )
          end

          def repository_kind_slugs
            'users|organizations'
          end
        end
      end
    end
  end
end
