# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Localization
      class LocaleSelector
        def initialize(supported:, default:)
          @supported = supported
          @default = default
        end

        def select(params:, cookies:, path_locale: nil)
          supported(path_locale) ||
            supported(params['lang']) ||
            supported(cookies['locale']) ||
            @default
        end

        private

        def supported(locale)
          @supported.include?(locale) ? locale : nil
        end
      end
    end
  end
end
