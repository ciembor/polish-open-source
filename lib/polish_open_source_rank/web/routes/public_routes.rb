# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      module PublicRoutes
        def self.registered(app)
          register_static_pages(app)
          register_ranking_routes(app)
          register_profile_routes(app)
        end

        class << self
          private

          def register_static_pages(app)
            register_metadata_routes(app)
            register_ranking_shortcuts(app)
            register_about_routes(app)
            register_edition_routes(app)
          end

          def register_metadata_routes(app)
            app.get '/robots.txt' do
              content_type 'text/plain'
              render_robots_txt
            end

            app.get('/sitemap.xml') { render_sitemap }
            app.get(%r{/sitemaps/(\d+)\.xml}) { |page| render_sitemap_page(Integer(page, 10)) }
          end

          def register_ranking_shortcuts(app)
            app.get('/') { redirect_canonical_public_path('/people') }
            app.get('/people') { render_rankings('latest', 'poland') }
            app.get('/latest') { redirect_canonical_public_path('/people') }
            app.get('/organizations') { render_rankings('latest', 'poland', section: 'organizations') }
            app.get('/organizations/locations/:slug') do
              render_city('latest', params.fetch('slug'), section: 'organizations')
            end
            app.get('/people/locations/:slug') { render_city('latest', params.fetch('slug')) }
          end

          def register_about_routes(app)
            app.get '/about' do
              @title = t('about.seo.title')
              @description = t('about.seo.description')
              @canonical_path = '/about'
              public_html_cache!('about')
              erb :'pages/about'
            end
          end

          def register_edition_routes(app)
            app.get('/editions') { render_editions }
            app.get(%r{/editions/(\d{4})}) { |year| render_editions(year) }
          end

          def register_profile_routes(app)
            app.get('/users/:platform/:login') { render_user_profile(params.fetch('platform'), params.fetch('login')) }
            app.get('/organizations/:platform/:login') do
              render_organization_profile(params.fetch('platform'), params.fetch('login'))
            end
            app.get('/repositories/:platform/:owner/:name') do
              render_repository_profile(params.fetch('platform'), params.fetch('owner'), params.fetch('name'))
            end
            app.get('/organization-repositories/:platform/:owner/:name') do
              render_organization_repository_profile(
                params.fetch('platform'),
                params.fetch('owner'),
                params.fetch('name')
              )
            end
          end

          def register_ranking_routes(app)
            register_latest_ranking_routes(app)
            register_historical_ranking_routes(app)
            register_location_shortcut_routes(app)
          end

          def register_latest_ranking_routes(app)
            LatestRankingRoutes.register(app)
          end

          def register_historical_ranking_routes(app)
            app.get(%r{/(\d{4}-\d{2})/#{app::RANKING_DETAIL_SEGMENTS}}) do |period_slug, kind, metric|
              render_ranking_detail(period_slug, 'poland', kind, metric)
            end
            app.get(
              %r{/(\d{4}-\d{2})/locations/([^/]+)/#{app::RANKING_DETAIL_SEGMENTS}}
            ) do |period_slug, slug, kind, metric|
              render_city_ranking_detail(period_slug, slug, kind, metric)
            end
            app.get(%r{/(\d{4}-\d{2})}) { |period_slug| render_rankings(period_slug, 'poland') }
            app.get(%r{/(\d{4}-\d{2})/organizations}) do |period_slug|
              render_rankings(period_slug, 'poland', section: 'organizations')
            end
            app.get(%r{/(\d{4}-\d{2})/organizations/locations/([^/]+)}) do |period_slug, slug|
              render_city(period_slug, slug, section: 'organizations')
            end
            app.get(%r{/(\d{4}-\d{2})/locations/([^/]+)}) { |period_slug, slug| render_city(period_slug, slug) }
          end

          def register_location_shortcut_routes(app)
            app.get('/locations/:slug') do
              redirect_canonical_public_path("/people/locations/#{params.fetch('slug')}")
            end
          end
        end
      end
    end
  end
end
