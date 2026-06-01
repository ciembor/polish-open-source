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
      include Controllers::LanguageController
      include Controllers::LanguageRepositoryRankingController
      include Controllers::PackageController
      include Controllers::PackageRankingController
      include Controllers::PublicController
      include Controllers::SharedController

      RANKING_DETAIL_SEGMENTS = '(users|repositories|organizations|organization-repositories)/' \
                                '(top|trending|active|members)'
      SUPPORTED_LOCALES = Boot::SUPPORTED_LOCALES
      DEFAULT_LOCALE = Boot::DEFAULT_LOCALE
      SESSION_COOKIE_KEY = Boot::SESSION_COOKIE_KEY

      Boot.configure(self)

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
        set_locale_cookie!(@locale) if persist_selected_locale?
        defer_anonymous_session_cookie! if anonymous_public_request?
      end

      not_found do
        status 404
        @title = t('not_found.title')
        @description = t('not_found.description')
        erb :'pages/not_found'
      end

      private

      def public_cache_revision(period)
        publication.cache_revision.for_period(period)
      end

      def latest_public_cache_key
        publication.cache_revision.latest_key(latest_period)
      end

      def html_revision
        settings.html_revision.value(locale: current_locale)
      end

      def locale_cookie_path
        configuration.app_base_path.empty? ? '/' : configuration.app_base_path
      end

      def set_locale_cookie!(locale)
        return if request.cookies['locale'] == locale

        response.set_cookie(
          'locale',
          value: locale,
          path: locale_cookie_path,
          max_age: 31_536_000,
          httponly: true,
          secure: configuration.rack_env == 'production',
          same_site: :lax
        )
      end

      def persist_selected_locale?
        return false unless request.get?
        return true if SUPPORTED_LOCALES.include?(params['lang'])
        return true if locale_prefix(request.path_info) == DEFAULT_LOCALE

        false
      end

      def anonymous_public_request?
        cacheable_public_method? &&
          !auth_path? &&
          !request.cookies.key?(SESSION_COOKIE_KEY) &&
          localizable_public_path?(env.fetch('polish_open_source_rank.unlocalized_path', request.path_info))
      end

      def cacheable_public_method?
        request.get? || request.head?
      end

      def defer_anonymous_session_cookie!
        env['rack.session.options'][:defer] = true
      end

      def asset_path(path)
        public_path = PolishOpenSourceRank.root.join('app/public', path.delete_prefix('/'))
        version = public_path.file? ? public_path.mtime.to_i : Time.now.to_i
        app_path("#{path}?v=#{version}")
      end

      def composition
        @composition ||= Composition.new(
          configuration: configuration,
          github_oauth_client: settings.github_oauth_client,
          discord_oauth_client: settings.discord_oauth_client,
          discord_gateway: settings.discord_gateway,
          discord_role_map: settings.discord_role_map
        )
      end

      def publication
        composition.publication
      end

      def packages
        composition.packages
      end

      def languages
        composition.languages
      end

      def community
        composition.community
      end

      def operations
        composition.operations
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
