# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    # Owns Sinatra setup so App can stay focused on request flow.
    module Boot
      SUPPORTED_LOCALES = %w[en pl].freeze
      DEFAULT_LOCALE = 'pl'
      SESSION_COOKIE_KEY = 'polish_open_source_rank.session'
      CSS_ASSET_FILES = [
        '/css/application.css',
        '/css/components/navigation.css',
        '/css/components/hero.css',
        '/css/components/rankings.css',
        '/css/pages/editions.css',
        '/css/pages/about.css',
        '/css/pages/profiles.css',
        '/css/components/notices.css',
        '/css/pages/operations.css',
        '/css/components/footer.css',
        '/css/responsive.css'
      ].freeze

      class << self
        def configure(app)
          ENV['TZ'] = 'Europe/Warsaw'
          configure_static_paths(app)
          configure_view_services(app)
          configure_injected_services(app)
          configure_middleware(app)
          configure_helpers(app)
          register_routes(app)
        end

        private

        def configure_static_paths(app)
          root = PolishOpenSourceRank.root
          app.set :public_folder, root.join('app/public').to_s
          app.set :views, root.join('app/views').to_s
          app.set :static_cache_control, [:public, :immutable, { max_age: 31_536_000 }]
        end

        def configure_view_services(app)
          configure_locale_services(app)
          configure_presentation_services(app)
        end

        def configure_locale_services(app)
          root = PolishOpenSourceRank.root
          app.set :default_locale, DEFAULT_LOCALE
          app.set :localized_text, Localization::TranslationCatalog.load(root: root, locales: SUPPORTED_LOCALES)
          app.set :locale_selector,
                  Localization::LocaleSelector.new(supported: SUPPORTED_LOCALES, default: DEFAULT_LOCALE)
          app.set :html_revision, HtmlRevision.new(root: root)
        end

        def configure_presentation_services(app)
          app.set :css_asset_files, CSS_ASSET_FILES
          app.set :badge_renderer, Presentation::BadgeRenderer.new
          app.set :platform_catalog, Presentation::PlatformCatalog.new
          app.set :ranking_catalog, Presentation::RankingCatalog.new
        end

        def configure_injected_services(app)
          app.set :github_oauth_client, nil
          app.set :discord_oauth_client, nil
          app.set :discord_gateway, nil
          app.set :discord_role_map, nil
        end

        def configure_middleware(app)
          configuration = Configuration.load
          Observability::Sentry.configure(configuration)
          app.use ::Sentry::Rack::CaptureExceptions if Observability::Sentry.configured?
          app.use RequestTelemetry
          app.use SecurityHeaders
          app.use RateLimiter
          app.use Rack::Deflater
          app.use Rack::Session::Cookie,
                  key: SESSION_COOKIE_KEY,
                  path: '/',
                  httponly: true,
                  secure: configuration.rack_env == 'production',
                  same_site: :lax,
                  secret: configuration.session_secret
        end

        def configure_helpers(app)
          app.helpers Presentation::LogoIconHelpers
          app.helpers Presentation::RoutingHelpers
          app.helpers Presentation::BadgeHelpers
          app.helpers Presentation::ViewHelpers
          app.helpers HttpCache
        end

        def register_routes(app)
          app.register Routes::LanguageRoutes
          app.register Routes::PackageRoutes
          app.register Routes::PublicRoutes
          app.register Routes::AuthRoutes
          app.register Routes::BadgeRoutes
          app.register Routes::InternalRoutes
        end
      end
    end
  end
end
