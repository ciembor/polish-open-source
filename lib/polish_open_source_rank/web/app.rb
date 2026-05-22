# frozen_string_literal: true

require 'sinatra/base'
require 'securerandom'
require 'digest'

module PolishOpenSourceRank
  module Web
    class App < Sinatra::Base
      include Controllers::AuthController
      include Controllers::BadgeController
      include Controllers::InternalController
      include Controllers::PublicController
      include Controllers::SharedController

      ENV['TZ'] = 'Europe/Warsaw'

      set :public_folder, PolishOpenSourceRank.root.join('app/public').to_s
      set :views, PolishOpenSourceRank.root.join('app/views').to_s

      RANKING_DETAIL_SEGMENTS = '(users|repositories)/(top|trending|active)'
      SUPPORTED_LOCALES = %w[en pl].freeze
      DEFAULT_LOCALE = 'pl'
      set :default_locale, DEFAULT_LOCALE
      set :localized_text,
          Localization::TranslationCatalog.load(root: PolishOpenSourceRank.root, locales: SUPPORTED_LOCALES)
      set :locale_selector, Localization::LocaleSelector.new(supported: SUPPORTED_LOCALES, default: DEFAULT_LOCALE)
      set :badge_renderer, Presentation::BadgeRenderer.new
      set :platform_catalog, Presentation::PlatformCatalog.new
      set :ranking_catalog, Presentation::RankingCatalog.new
      set :static_cache_control, [:public, :immutable, { max_age: 31_536_000 }]
      set :github_oauth_client, nil
      set :discord_oauth_client, nil
      set :discord_gateway, nil
      set :discord_role_map, Contexts::Community::Infrastructure::Discord::DiscordRoleMap.new
      use Rack::Session::Cookie,
          key: 'polish_open_source_rank.session',
          path: '/',
          same_site: :lax,
          secret: Configuration.load.session_secret
      helpers Presentation::RoutingHelpers
      helpers Presentation::BadgeHelpers
      helpers Presentation::ViewHelpers
      helpers HttpCache

      register Routes::PublicRoutes
      register Routes::AuthRoutes
      register Routes::BadgeRoutes
      register Routes::InternalRoutes

      before do
        redirect_param_locale! if request.get?
        rewrite_locale_path!
        no_store! if auth_path?
        @locale = settings.locale_selector.select(
          path_locale: env.fetch('polish_open_source_rank.path_locale', nil),
          params: params,
          cookies: request.cookies,
          accept_language: request.env.fetch('HTTP_ACCEPT_LANGUAGE', nil)
        )
        redirect_to_locale_variant! if request.get?
        set_locale_cookie!(@locale)
      end

      not_found do
        status 404
        @title = t('not_found.title')
        @description = t('not_found.description')
        erb :not_found
      end

      private

      def public_cache_revision(period)
        cache_revision_read_model.public_cache_revision(period) || 'empty'
      end

      def latest_public_cache_key
        period = latest_period
        "#{period}:#{public_cache_revision(period)}"
      end

      def html_revision
        files_revision(
          'app/views/layout.erb',
          'app/views/about.erb',
          'app/views/editions.erb',
          'app/views/ranking_detail.erb',
          'app/views/rankings.erb',
          'app/views/repository_profile.erb',
          'app/views/user_profile.erb',
          'app/public/css/application.css',
          "config/locales/#{current_locale}.yml"
        )
      end

      def files_revision(*relative_paths)
        relative_paths.map { |path| PolishOpenSourceRank.root.join(path).mtime.to_i }.max
      end

      def locale_cookie_path
        configuration.app_base_path.empty? ? '/' : configuration.app_base_path
      end

      def set_locale_cookie!(locale)
        response.set_cookie(
          'locale',
          value: locale,
          path: locale_cookie_path,
          max_age: 31_536_000,
          same_site: :lax
        )
      end

      def asset_path(path)
        public_path = PolishOpenSourceRank.root.join('app/public', path.delete_prefix('/'))
        version = public_path.file? ? public_path.mtime.to_i : Time.now.to_i
        app_path("#{path}?v=#{version}")
      end

      def database
        @database ||= begin
          db = Shared::Infrastructure::SQLite::Database.open(configuration.database_path)
          Infrastructure::PlatformSchemaMigration.new(db, Infrastructure::SQLiteSchema.sql).bootstrap!
          db
        end
      end

      def show_rankings
        @show_rankings ||= Contexts::Publication::Application::ShowRankings.new(ranking_read_model: ranking_read_model)
      end

      def show_ranking_detail
        @show_ranking_detail ||=
          Contexts::Publication::Application::ShowRankingDetail.new(ranking_read_model: ranking_read_model)
      end

      def list_editions
        @list_editions ||= Contexts::Publication::Application::ListEditions.new(edition_read_model: edition_read_model)
      end

      def show_user_profile
        @show_user_profile ||=
          Contexts::Publication::Application::ShowUserProfile.new(profile_read_model: profile_read_model)
      end

      def show_repository_profile
        @show_repository_profile ||=
          Contexts::Publication::Application::ShowRepositoryProfile.new(profile_read_model: profile_read_model)
      end

      def render_badge
        @render_badge ||= Contexts::Publication::Application::RenderBadge.new(profile_read_model: profile_read_model)
      end

      def resolve_period
        @resolve_period ||= Contexts::Publication::Application::ResolvePeriod.new(
          period_read_model: cache_revision_read_model
        )
      end

      def show_job_progress
        @show_job_progress ||= Contexts::Operations::Application::ShowJobProgress.new(
          read_model: job_progress_read_model
        )
      end

      def show_discord_panel
        @show_discord_panel ||= Contexts::Community::Application::ShowDiscordPanel.new(
          connection_repository: discord_connection_repository,
          access_read_model: contributor_access_read_model
        )
      end

      def connect_discord_account
        @connect_discord_account ||= Contexts::Community::Application::ConnectDiscordAccount.new(
          profile_read_model: profile_read_model,
          connection_repository: discord_connection_repository,
          access_read_model: contributor_access_read_model,
          member_gateway: discord_gateway,
          role_map: discord_role_map
        )
      end

      def cache_revision_read_model
        @cache_revision_read_model ||=
          Contexts::Publication::Infrastructure::SQLite::SQLiteCacheRevisionReadModel.new(database)
      end

      def ranking_read_model
        @ranking_read_model ||= Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingReadModel.new(database)
      end

      def edition_read_model
        @edition_read_model ||= Contexts::Publication::Infrastructure::SQLite::SQLiteEditionReadModel.new(
          database,
          ranking_read_model: ranking_read_model
        )
      end

      def profile_read_model
        @profile_read_model ||= Contexts::Publication::Infrastructure::SQLite::SQLiteProfileReadModel.new(database)
      end

      def contributor_access_read_model
        @contributor_access_read_model ||=
          Contexts::Community::Infrastructure::SQLite::SQLiteContributorAccessReadModel.new(database)
      end

      def discord_connection_repository
        @discord_connection_repository ||=
          Contexts::Community::Infrastructure::SQLite::SQLiteDiscordConnectionRepository.new(database)
      end

      def job_progress_read_model
        @job_progress_read_model ||=
          Contexts::Operations::Infrastructure::SQLite::SQLiteJobProgressReadModel.new(database)
      end

      def ranking_metric?(kind, metric)
        settings.ranking_catalog.include?(kind, metric)
      end

      def ranking_title(kind, metric)
        t(settings.ranking_catalog.descriptor(kind, metric).title_key)
      end

      def ranking_metric_column(kind, metric)
        settings.ranking_catalog.descriptor(kind, metric).column
      end

      def ranking_metric_label(kind, metric)
        t(settings.ranking_catalog.descriptor(kind, metric).label_key)
      end

      def scope_data(scope)
        return { slug: 'poland', name: 'Polska', type: :country } if scope == 'poland'

        Contexts::Ranking::Domain::LocationCatalog::CITY_BY_SLUG.fetch(scope)
      end

      def redirect_param_locale!
        locale = params['lang']
        return unless SUPPORTED_LOCALES.include?(locale)

        path = strip_locale_prefix(request.path_info)
        return unless localizable_public_path?(path)

        set_locale_cookie!(locale)
        redirect localized_public_path(path, locale: locale, query: locale_query_without_lang), 302
      end

      def rewrite_locale_path!
        env['polish_open_source_rank.original_path'] ||= request.path_info
        locale = locale_prefix(request.path_info)
        return unless locale

        path = strip_locale_prefix(request.path_info)
        if locale == DEFAULT_LOCALE
          set_locale_cookie!(locale)
          redirect localized_public_path(path, locale: DEFAULT_LOCALE, query: current_query), 302
        end

        env['polish_open_source_rank.path_locale'] = locale
        env['polish_open_source_rank.unlocalized_path'] = path
        env['PATH_INFO'] = path
      end

      def redirect_to_locale_variant!
        path = env.fetch('polish_open_source_rank.unlocalized_path', request.path_info)
        return unless localizable_public_path?(path)
        return if env.key?('polish_open_source_rank.path_locale')
        return if @locale == DEFAULT_LOCALE

        redirect localized_public_path(path, locale: @locale, query: current_query), 302
      end

      def locale_prefix(path)
        Localization::PublicPathPolicy.locale_prefix(path)
      end

      def strip_locale_prefix(path)
        Localization::PublicPathPolicy.strip_locale_prefix(path)
      end

      def localizable_public_path?(path)
        Localization::PublicPathPolicy.localizable?(path)
      end

      def localized_public_path(path, locale:, query: nil)
        localized_path = Localization::PublicPathPolicy.localized(
          path: path,
          locale: locale,
          default_locale: DEFAULT_LOCALE
        )
        query ? "#{localized_path}?#{Rack::Utils.build_query(query)}" : localized_path
      end

      def current_query
        query = Rack::Utils.parse_nested_query(request.query_string)
        query.empty? ? nil : query
      end

      def locale_query_without_lang
        query = Rack::Utils.parse_nested_query(request.query_string)
        query.delete('lang')
        query.empty? ? nil : query
      end
    end
  end
end
