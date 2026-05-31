# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module ViewHelpers
        METRIC_ICONS = {
          total_stars: '⭐',
          monthly_stars_delta: '⭐',
          stargazers_count: '⭐',
          repository_stars_count: '⭐',
          repository_stars_delta: '⭐',
          downloads_30d: '📥',
          downloads_7d: '📥',
          downloads_total: '📥',
          merged_pull_requests_count: '🔀'
        }.freeze

        def h(value)
          Rack::Utils.escape_html(value.to_s)
        end

        def number(value)
          value.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1 ').reverse
        end

        def metric_value(metric, value)
          icon = METRIC_ICONS[metric.to_sym]
          formatted = number(value)
          icon ? "#{icon} #{formatted}" : formatted
        end

        def t(key, values = {})
          settings.localized_text.translate(current_locale, key, values)
        end

        def platform_name(platform)
          settings.platform_catalog.name(platform)
        end

        def platform_icon_path(platform)
          settings.platform_catalog.icon_path(platform)
        end

        def scopes
          Contexts::Ranking::Domain::LocationCatalog.scopes
        end

        def elite_medal_path(rank)
          case rank.to_i
          when 1 then '/icons/medal-gold.svg'
          when 2 then '/icons/medal-silver.svg'
          when 3 then '/icons/medal-bronze.svg'
          end
        end

        def period_label(period_start)
          date = Date.parse(period_start)
          "#{t('date.months').fetch(date.month - 1)} #{date.year}"
        end

        def scope_name(scope)
          return t('scope.poland') if scope.fetch(:slug) == 'poland'

          scope.fetch(:name)
        end
      end
    end
  end
end
