# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module PackagePathHelpers
        PACKAGE_ECOSYSTEM_NAMES = {
          'apt' => 'APT',
          'clojars' => 'Clojars',
          'conda' => 'Conda',
          'conan' => 'Conan',
          'cpan' => 'CPAN',
          'cran' => 'CRAN',
          'crates' => 'crates.io',
          'go' => 'Go modules',
          'hackage' => 'Hackage',
          'hex' => 'Hex',
          'homebrew' => 'Homebrew',
          'julia' => 'Julia packages',
          'maven' => 'Maven',
          'nix' => 'Nix',
          'npm' => 'npm',
          'nuget' => 'NuGet',
          'packagist' => 'Packagist',
          'pub' => 'pub.dev',
          'pypi' => 'PyPI',
          'rpm' => 'RPM',
          'rubygems' => 'RubyGems',
          'swiftpm' => 'Swift Package Manager',
          'terraform' => 'Terraform Registry',
          'vcpkg' => 'vcpkg'
        }.freeze

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

        def package_metric_label(metric, ecosystem: nil)
          return t('packages.metric.installs.30d') if ecosystem == 'homebrew' && metric.to_s == 'downloads_30d'

          t("packages.metric.#{metric.to_s.tr('_', '.')}")
        end

        def package_ecosystem_name(ecosystem)
          PACKAGE_ECOSYSTEM_NAMES.fetch(ecosystem, ecosystem)
        end

        def package_ecosystem_icon_path(ecosystem)
          extension = %w[packagist].include?(ecosystem) ? 'png' : 'svg'
          extension = 'ico' if %w[rubygems vcpkg].include?(ecosystem)
          "/icons/package_ecosystems/#{ecosystem}.#{extension}"
        end

        def package_ecosystem_description(ecosystem)
          t(
            'packages.ecosystem.card_description',
            ecosystem: package_ecosystem_name(ecosystem),
            scope: t("packages.ecosystem.scope.#{ecosystem}")
          )
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
