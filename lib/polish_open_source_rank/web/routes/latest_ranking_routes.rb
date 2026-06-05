# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      module LatestRankingRoutes
        class << self
          def register(app)
            register_current_people_routes(app)
            register_current_organization_routes(app)
            register_legacy_redirects(app)
          end

          private

          def register_current_people_routes(app)
            app.get(%r{/people/(users|repositories)/(top|trending|active|members)}) do |kind, metric|
              render_ranking_detail('latest', 'poland', kind, metric)
            end
            app.get(people_city_ranking_route) do |slug, kind, metric|
              render_city_ranking_detail('latest', slug, kind, metric)
            end
          end

          def register_current_organization_routes(app)
            app.get(%r{/organizations/(top|trending|active|members)}) do |metric|
              render_ranking_detail('latest', 'poland', 'organizations', metric)
            end
            app.get(%r{/organizations/repositories/(top|trending|active|members)}) do |metric|
              render_ranking_detail('latest', 'poland', 'organization-repositories', metric)
            end
            app.get(%r{/organizations/locations/([^/]+)/(top|trending|active|members)}) do |slug, metric|
              render_city_ranking_detail('latest', slug, 'organizations', metric)
            end
            app.get(organization_city_repository_ranking_route) do |slug, metric|
              render_city_ranking_detail('latest', slug, 'organization-repositories', metric)
            end
          end

          def register_legacy_redirects(app)
            app.get('/latest/locations/:slug') do
              redirect_canonical_public_path("/people/locations/#{params.fetch('slug')}")
            end
            app.get('/latest/organizations') { redirect_canonical_public_path('/organizations') }
            app.get('/latest/organizations/locations/:slug') do
              redirect_canonical_public_path("/organizations/locations/#{params.fetch('slug')}")
            end
            app.get(%r{/latest/#{app::RANKING_DETAIL_SEGMENTS}}) do |kind, metric|
              redirect_canonical_public_path(latest_ranking_path(kind, metric, scope_slug: 'poland'))
            end
            app.get(%r{/latest/locations/([^/]+)/#{app::RANKING_DETAIL_SEGMENTS}}) do |slug, kind, metric|
              redirect_canonical_public_path(latest_ranking_path(kind, metric, scope_slug: slug))
            end
          end

          def people_city_ranking_route
            %r{/people/locations/([^/]+)/(users|repositories)/(top|trending|active|members)}
          end

          def organization_city_repository_ranking_route
            %r{/organizations/locations/([^/]+)/repositories/(top|trending|active|members)}
          end
        end
      end
    end
  end
end
