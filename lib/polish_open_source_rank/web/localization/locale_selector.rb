# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Localization
      class LocaleSelector
        def initialize(supported:, default:)
          @supported = supported
          @default = default
        end

        def select(params:, cookies:, accept_language:)
          supported(params['lang']) || supported(cookies['locale']) || accepted(accept_language) || @default
        end

        private

        def accepted(header)
          header.to_s.split(',').filter_map do |language|
            supported(language.split(';', 2).first.to_s.strip.split('-', 2).first)
          end.first
        end

        def supported(locale)
          @supported.include?(locale) ? locale : nil
        end
      end
    end
  end
end
