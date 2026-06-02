# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      class SitemapEntries
        def initialize(context, catalog:, generated_on: Time.now.utc.strftime('%Y-%m-%d'))
          @context = context
          @catalog = catalog
          @generated_on = generated_on
        end

        def call
          locale_variants(catalog.paths(latest_period: latest_period)).map do |path|
            { loc: full_url(app_path(path)), lastmod: generated_on }
          end
        end

        private

        attr_reader :context, :catalog, :generated_on

        def locale_variants(paths)
          paths.flat_map { |path| [path, localized_public_path(path, locale: 'en')] }
        end

        def full_url(path)
          context.__send__(:full_url, path)
        end

        def app_path(path)
          context.__send__(:app_path, path)
        end

        def localized_public_path(path, locale:)
          context.__send__(:localized_public_path, path, locale: locale)
        end

        def latest_period
          context.__send__(:latest_period)
        end
      end
    end
  end
end
