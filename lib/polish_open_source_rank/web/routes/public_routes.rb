# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      module PublicRoutes
        def self.registered(app)
          register_static_pages(app)
          register_profile_routes(app)
          register_ranking_routes(app)
        end

        class << self
          private

          def register_static_pages(app)
            app.get '/robots.txt' do
              content_type 'text/plain'
              render_robots_txt
            end

            app.get '/sitemap.xml' do
              content_type 'application/xml'
              render_sitemap
            end

            app.get('/') { render_rankings('latest', 'poland') }
            app.get('/latest') { render_rankings('latest', 'poland') }

            app.get '/about' do
              @title = t('about.seo.title')
              @description = t('about.seo.description')
              @canonical_path = '/about'
              public_html_cache!('about')
              erb :about
            end

            app.get('/editions') { render_editions }
            app.get(%r{/editions/(\d{4})}) { |year| render_editions(year) }
          end

          def register_profile_routes(app)
            app.get('/users/:platform/:login') { render_user_profile(params.fetch('platform'), params.fetch('login')) }
            app.get('/repositories/:platform/:owner/:name') do
              render_repository_profile(params.fetch('platform'), params.fetch('owner'), params.fetch('name'))
            end
          end

          def register_ranking_routes(app)
            app.get('/latest/locations/:slug') { render_city('latest', params.fetch('slug')) }
            app.get(%r{/latest/#{app::RANKING_DETAIL_SEGMENTS}}) do |kind, metric|
              render_ranking_detail('latest', 'poland', kind, metric)
            end
            app.get(%r{/latest/locations/([^/]+)/#{app::RANKING_DETAIL_SEGMENTS}}) do |slug, kind, metric|
              render_city_ranking_detail('latest', slug, kind, metric)
            end
            app.get(%r{/(\d{4}-\d{2})/#{app::RANKING_DETAIL_SEGMENTS}}) do |period_slug, kind, metric|
              render_ranking_detail(period_slug, 'poland', kind, metric)
            end
            app.get(
              %r{/(\d{4}-\d{2})/locations/([^/]+)/#{app::RANKING_DETAIL_SEGMENTS}}
            ) do |period_slug, slug, kind, metric|
              render_city_ranking_detail(period_slug, slug, kind, metric)
            end
            app.get(%r{/(\d{4}-\d{2})}) { |period_slug| render_rankings(period_slug, 'poland') }
            app.get(%r{/(\d{4}-\d{2})/locations/([^/]+)}) { |period_slug, slug| render_city(period_slug, slug) }
            app.get('/locations/:slug') { render_city('latest', params.fetch('slug')) }
          end
        end
      end
    end
  end
end
