# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module RoutingHelpers
        include PackagePathHelpers
        include ProfilePathHelpers
        include StructuredDataHelpers

        def current_locale
          @locale || settings.default_locale
        end

        def current_locale?(locale)
          current_locale == locale
        end

        def locale_path(locale)
          query = Rack::Utils.parse_nested_query(request.query_string)
          query.delete('lang')
          query['lang'] = locale if locale == settings.default_locale && !current_locale?(locale)

          path = localized_public_path(unlocalized_request_path, locale: locale)
          return path if query.empty?

          "#{path}?#{Rack::Utils.build_query(query)}"
        end

        def city_path(slug, period_slug: @period_slug)
          "#{period_base_path(period_slug)}/locations/#{slug}"
        end

        def scope_path(scope, period_slug: @period_slug)
          return period_base_path(period_slug) if scope.fetch(:slug) == 'poland'

          city_path(scope.fetch(:slug), period_slug: period_slug)
        end

        def ranking_path(kind, metric, period_slug: @period_slug, scope_slug: @scope.fetch(:slug))
          "#{scope_path({ slug: scope_slug }, period_slug: period_slug)}/#{kind}/#{metric}"
        end

        def period_base_path(period_slug)
          path = period_slug.nil? || period_slug == 'latest' ? '/latest' : "/#{period_slug}"
          localized_public_path(path, locale: current_locale)
        end

        def app_path(path)
          "#{configuration.app_base_path}#{path}"
        end

        def editions_path(year = nil)
          localized_public_path(year ? "/editions/#{year}" : '/editions', locale: current_locale)
        end

        def canonical_url
          full_url(canonical_path)
        end

        def alternate_locale_urls
          return {} unless localized_page?

          App::SUPPORTED_LOCALES.to_h do |locale|
            [locale, full_url(localized_public_path(canonical_path, locale: locale))]
          end
        end

        def social_image_url
          full_url(app_path(social_image_path))
        end

        def open_graph_type
          return 'profile' if @profile || @organization || @repository || @organization_repository

          'website'
        end

        def og_locale
          current_locale == 'pl' ? 'pl_PL' : 'en_US'
        end

        def og_alternate_locales
          App::SUPPORTED_LOCALES.reject { |locale| locale == current_locale }.map do |locale|
            locale == 'pl' ? 'pl_PL' : 'en_US'
          end
        end

        def configuration
          @configuration ||= Configuration.load
        end

        private

        def canonical_path
          path = @canonical_path || request.path_info
          return path if localized_path?(path)
          return localized_public_path(path, locale: current_locale) if localized_page_path?(path)

          path
        end

        def localized_page?
          localized_page_path?(canonical_path)
        end

        def localized_public_path(path, locale:)
          Localization::PublicPathPolicy.localized(path: path, locale: locale, default_locale: settings.default_locale)
        end

        def localized_path?(path)
          !Localization::PublicPathPolicy.locale_prefix(path).nil?
        end

        def localized_page_path?(path)
          Localization::PublicPathPolicy.localizable?(path)
        end

        def unlocalized_request_path
          env.fetch('polish_open_source_rank.unlocalized_path', request.path_info)
        end

        def full_url(path)
          base_url = configuration.public_base_url.delete_suffix('/')
          "#{base_url}#{path}"
        end

        def social_image_path
          return '/images/polish_open_source_front.webp' if about_page?
          return '/images/polish_open_source_front.webp' if @editions
          return '/images/polish_open_source_front.webp' if profile_page? || repository_page?

          '/images/polish_open_source_banner.webp'
        end

        def present_value?(value)
          !value.to_s.empty?
        end
      end
    end
  end
end
