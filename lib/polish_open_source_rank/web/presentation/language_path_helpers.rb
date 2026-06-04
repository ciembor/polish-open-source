# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module LanguagePathHelpers
        LANGUAGE_ICON_OVERRIDES = {
          'C#' => 'c_sharp',
          'C++' => 'c_plus_plus',
          'Emacs Lisp' => 'emacs_lisp',
          'F#' => 'f_sharp',
          'Game Maker Language' => 'game_maker_language',
          'Go Template' => 'go_template',
          'Jupyter Notebook' => 'jupyter_notebook',
          'Objective-C' => 'objective_c',
          'Objective-C++' => 'objective_c_plus_plus',
          'Open Policy Agent' => 'open_policy_agent',
          'PLpgSQL' => 'plpgsql',
          'Ren\'Py' => 'ren_py',
          'Vim Script' => 'vim_script',
          'Visual Basic .NET' => 'visual_basic_dot_net'
        }.freeze
        LANGUAGE_ICON_EXTENSIONS = {
          'Apex' => 'ico',
          'Common Lisp' => 'ico',
          'Freemarker' => 'png',
          'Haxe' => 'ico',
          'LabVIEW' => 'png',
          'Odin' => 'png',
          'Objective-C' => 'ico',
          'Open Policy Agent' => 'ico',
          'Ren\'Py' => 'ico',
          'RobotFramework' => 'ico'
        }.freeze

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

        def language_icon_exists?(language)
          logo_icon_exists?(language_icon_path(language))
        end

        def language_initial(language)
          logo_icon_initial(language)
        end

        def language_repository_ranking_path(language, repository_kind, metric_slug, period_slug: @period_slug)
          [
            language_path(language, period_slug: period_slug),
            language_repository_kind_slug(repository_kind),
            metric_slug
          ].join('/')
        end

        def language_metric_label(metric)
          t("languages.metric.#{metric.to_s.tr('_', '.')}")
        end

        def language_icon_path(language)
          extension = LANGUAGE_ICON_EXTENSIONS.fetch(language, 'svg')
          "/icons/languages/#{language_icon_slug(language)}.#{extension}"
        end

        def language_icon_slug(language)
          LANGUAGE_ICON_OVERRIDES.fetch(language) do
            language.downcase.tr('#+', '').gsub(/[^a-z0-9]+/, '_').delete_suffix('_')
          end
        end

        def language_repository_kind_label(repository_kind)
          t("languages.repository_kind.#{language_repository_kind_key(repository_kind)}")
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

        def language_repository_kind_key(repository_kind)
          repository_kind.nil? ? 'all' : repository_kind.to_s
        end

        def language_repository_kind_slug(repository_kind)
          language_repository_kind_key(repository_kind) == 'all' ? 'repositories' : "#{repository_kind}s"
        end
      end
    end
  end
end
