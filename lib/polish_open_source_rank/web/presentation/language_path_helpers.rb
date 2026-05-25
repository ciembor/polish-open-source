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

        def language_path(language, period_slug: @period_slug)
          prefix = period_slug.nil? || period_slug == 'latest' ? '/latest' : "/#{period_slug}"
          localized_public_path("#{prefix}/languages/#{Rack::Utils.escape_path(language)}", locale: current_locale)
        end

        def language_repository_ranking_path(language, repository_kind, metric_slug, period_slug: @period_slug)
          "#{language_path(language, period_slug: period_slug)}/#{repository_kind}s/#{metric_slug}"
        end

        def language_metric_label(metric)
          t("languages.metric.#{metric.to_s.tr('_', '.')}")
        end

        def language_repository_kind_label(repository_kind)
          t("languages.repository_kind.#{repository_kind}")
        end

        def language_repository_ranking_title(language, repository_kind, metric_slug)
          t(
            "languages.repository_ranking_title.#{metric_slug}",
            language: language,
            kind: language_repository_kind_label(repository_kind)
          )
        end

        def language_repository_ranking_preview_title(metric_slug)
          t("languages.repository_ranking_preview_title.#{metric_slug}")
        end

        def language_ranking_title(metric_slug)
          t("languages.ranking_title.#{metric_slug}")
        end

        def language_ranking_preview_title(metric_slug)
          t("languages.ranking_preview_title.#{metric_slug}")
        end
      end
    end
  end
end
