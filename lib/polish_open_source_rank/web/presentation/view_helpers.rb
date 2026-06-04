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
          dependents_count: '🔗',
          dependent_repositories_count: '🔗',
          members_count: '👥',
          merged_pull_requests_count: '🚀'
        }.freeze
        DOWNLOAD_METRICS = %i[downloads_30d downloads_7d downloads_total].freeze
        COMPACT_NUMBER_UNITS = [
          [1_000_000_000, { pl: 'mld', en: 'B' }],
          [1_000_000, { pl: 'mln', en: 'M' }],
          [1_000, { pl: 'tys.', en: 'K' }]
        ].freeze
        def h(value)
          Rack::Utils.escape_html(value.to_s)
        end

        def safe_external_url(value)
          SafeExternalUrl.normalize(value)
        end

        def number(value)
          value.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1 ').reverse
        end

        def metric_value(metric, value)
          icon = METRIC_ICONS[metric.to_sym]
          formatted = metric_number(metric, value)
          icon ? "#{icon} #{formatted}" : formatted
        end

        def metric_number(metric, value)
          return compact_number(value) if DOWNLOAD_METRICS.include?(metric.to_sym)

          number(value)
        end

        def compact_number(value)
          integer = value.to_i
          divisor, units = COMPACT_NUMBER_UNITS.find { |threshold, _units| integer >= threshold }
          return number(integer) unless divisor

          compact_value = compact_number_value(integer, divisor)
          compact_number_with_unit(compact_value, units)
        end

        def compact_number_value(value, divisor)
          scaled = value.to_f / divisor
          return scaled.floor.to_s if scaled >= 10

          ((scaled * 10).floor / 10.0).to_s.sub(/\.0\z/, '')
        end

        def compact_number_with_unit(value, units)
          unit = units.fetch(current_locale.to_sym, units.fetch(:en))
          return "#{value}#{unit}" if current_locale.to_sym == :en

          "#{value.tr('.', ',')} #{unit}"
        end

        def star_history_chart_url(record)
          repository = star_history_repository_name(record)
          return nil unless repository

          query = { repos: repository, type: 'date', legend: 'top-left' }
          "https://api.star-history.com/chart?#{Rack::Utils.build_query(query)}"
        end

        def star_history_page_url(record)
          repository = star_history_repository_name(record)
          return nil unless repository

          owner, name = repository.split('/', 2)
          "https://www.star-history.com/#{Rack::Utils.escape_path(owner)}/#{Rack::Utils.escape_path(name)}"
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

        def star_history_repository_name(record)
          return nil unless record.fetch(:platform, nil) == 'github'

          repository = record.fetch(:full_name, nil).to_s
          return nil unless repository.match?(%r{\A[\w.-]+/[\w.-]+\z})

          repository
        end
      end
    end
  end
end
