# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module LanguagePathHelpers
        def language_index_path(period_slug: @period_slug)
          path = period_slug.nil? || period_slug == 'latest' ? '/languages' : "/#{period_slug}/languages"
          localized_public_path(path, locale: current_locale)
        end

        def language_ranking_path(metric_slug, period_slug: @period_slug)
          prefix = period_slug.nil? || period_slug == 'latest' ? '/latest' : "/#{period_slug}"
          localized_public_path("#{prefix}/languages/#{metric_slug}", locale: current_locale)
        end

        def language_metric_label(metric)
          t("languages.metric.#{metric.to_s.tr('_', '.')}")
        end

        def language_ranking_title(metric_slug)
          t("languages.ranking_title.#{metric_slug}")
        end
      end
    end
  end
end
