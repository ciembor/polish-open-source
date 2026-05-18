# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module ViewHelpers
        def h(value)
          Rack::Utils.escape_html(value.to_s)
        end

        def number(value)
          value.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1 ').reverse
        end

        def t(key, values = {})
          settings.localized_text.translate(current_locale, key, values)
        end

        def current_locale
          @locale || settings.default_locale
        end

        def current_locale?(locale)
          current_locale == locale
        end

        def locale_path(locale)
          query = Rack::Utils.parse_nested_query(request.query_string)
          query.delete('lang')
          query['lang'] = locale
          "#{app_path(request.path_info)}?#{Rack::Utils.build_query(query)}"
        end

        def platform_name(platform)
          settings.platform_catalog.name(platform)
        end

        def platform_icon_path(platform)
          settings.platform_catalog.icon_path(platform)
        end

        def scopes
          Domain::LocationCatalog.scopes
        end

        def primary_city_scopes
          Domain::LocationCatalog.primary_city_scopes
        end

        def secondary_city_scopes
          Domain::LocationCatalog.secondary_city_scopes
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

        def user_profile_path(user)
          platform = Rack::Utils.escape_path(user.fetch(:platform, 'github'))
          login = Rack::Utils.escape_path(user.fetch(:login))
          "/users/#{platform}/#{login}"
        end

        def repository_profile_path(repository)
          platform = Rack::Utils.escape_path(repository.fetch(:platform, 'github'))
          owner, name = repository.fetch(:full_name).split('/', 2)
          "/repositories/#{platform}/#{Rack::Utils.escape_path(owner)}/#{Rack::Utils.escape_path(name)}"
        end

        def elite_medal_path(rank)
          case rank.to_i
          when 1 then '/icons/medal-gold.svg'
          when 2 then '/icons/medal-silver.svg'
          when 3 then '/icons/medal-bronze.svg'
          end
        end

        def period_base_path(period_slug)
          return '/latest' if period_slug.nil? || period_slug == 'latest'

          "/#{period_slug}"
        end

        def app_path(path)
          "#{configuration.app_base_path}#{path}"
        end

        def editions_path(year = nil)
          year ? "/editions/#{year}" : '/editions'
        end

        def period_label(period_start)
          date = Date.parse(period_start)
          "#{t('date.months').fetch(date.month - 1)} #{date.year}"
        end

        def scope_name(scope)
          return t('scope.poland') if scope.fetch(:slug) == 'poland'

          scope.fetch(:name)
        end

        def canonical_url
          base_url = configuration.public_base_url.delete_suffix('/')
          "#{base_url}#{@canonical_path || request.path_info}"
        end

        def structured_data
          JSON.pretty_generate(
            '@context' => 'https://schema.org',
            '@type' => 'Dataset',
            'name' => @title,
            'description' => @description,
            'url' => canonical_url
          )
        end

        def configuration
          @configuration ||= Configuration.load
        end
      end
    end
  end
end
