# frozen_string_literal: true

require 'base64'

module PolishOpenSourceRank
  module Web
    module Presentation
      module PackagePathHelpers
        def package_index_path(period_slug: @period_slug)
          path = period_slug.nil? || period_slug == 'latest' ? '/packages' : "/#{period_slug}/packages"
          localized_public_path(path, locale: current_locale)
        end

        def package_ecosystem_path(ecosystem, period_slug: @period_slug)
          prefix = period_slug.nil? || period_slug == 'latest' ? '/latest' : "/#{period_slug}"
          path = "#{prefix}/packages/#{Rack::Utils.escape_path(ecosystem)}"
          localized_public_path(path, locale: current_locale)
        end

        def package_ranking_path(ecosystem, metric_slug, period_slug: @period_slug)
          "#{package_ecosystem_path(ecosystem, period_slug: period_slug)}/#{metric_slug}"
        end

        def package_repository_ranking_path(ecosystem, repository_kind, metric_slug, period_slug: @period_slug)
          "#{package_ecosystem_path(ecosystem, period_slug: period_slug)}/#{repository_kind}s/#{metric_slug}"
        end

        def package_profile_path(package)
          ecosystem = Rack::Utils.escape_path(package.fetch(:ecosystem))
          encoded_name = package_name_slug(package.fetch(:package_name))
          localized_public_path("/packages/#{ecosystem}/names/#{encoded_name}", locale: current_locale)
        end

        def package_name_slug(package_name)
          Base64.urlsafe_encode64(package_name, padding: false)
        end

        def decode_package_name_slug(slug)
          padding = '=' * ((4 - (slug.length % 4)) % 4)
          Base64.urlsafe_decode64("#{slug}#{padding}")
        rescue ArgumentError
          nil
        end

        def package_metric_label(metric, ecosystem: nil)
          return t('packages.metric.installs.30d') if ecosystem == 'homebrew' && metric.to_s == 'downloads_30d'

          t("packages.metric.#{metric.to_s.tr('_', '.')}")
        end

        def package_ranking_title(metric_slug, ecosystem:)
          return t('packages.ranking_title.installs') if ecosystem == 'homebrew' && metric_slug.to_s == 'top'

          t("packages.ranking_title.#{metric_slug}", ecosystem: ecosystem)
        end

        def package_ranking_preview_title(metric_slug, ecosystem:)
          return t('packages.ranking_preview_title.installs') if ecosystem == 'homebrew' && metric_slug.to_s == 'top'

          t("packages.ranking_preview_title.#{metric_slug}", ecosystem: ecosystem)
        end

        def package_repository_kind_label(repository_kind)
          t("packages.repository_kind.#{repository_kind}")
        end

        def package_repository_ranking_title(metric_slug, ecosystem:, repository_kind:)
          t(
            "packages.repository_ranking_title.#{metric_slug}",
            ecosystem: ecosystem,
            kind: package_repository_kind_label(repository_kind)
          )
        end

        def package_repository_ranking_preview_title(metric_slug, ecosystem:)
          return t('packages.ranking_preview_title.installs') if ecosystem == 'homebrew' && metric_slug.to_s == 'top'

          t("packages.ranking_preview_title.#{metric_slug}", ecosystem: ecosystem)
        end
      end
    end
  end
end
