# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Localization
      class PublicPathPolicy
        ROOT_PATHS = ['/', '/latest', '/about', '/editions', '/languages'].freeze
        PREFIX_PATHS = [
          '/latest/',
          '/editions/',
          '/languages/',
          '/packages',
          '/packages/',
          '/users/',
          '/organizations/',
          '/repositories/',
          '/organization-repositories/'
        ].freeze
        PERIOD_PATTERN = %r{\A/\d{4}-\d{2}(?:/|\z)}
        LOCALE_PATTERN = %r{\A/(en|pl)(?=/|\z)}

        class << self
          def locale_prefix(path)
            LOCALE_PATTERN.match(path)&.captures&.first
          end

          def strip_locale_prefix(path)
            stripped = path.sub(LOCALE_PATTERN, '')
            stripped.empty? ? '/' : stripped
          end

          def localizable?(path)
            ROOT_PATHS.include?(path) ||
              PREFIX_PATHS.any? { |prefix| path.start_with?(prefix) } ||
              PERIOD_PATTERN.match?(path)
          end

          def localized(path:, locale:, default_locale:)
            normalized_path = path == '' ? '/' : path
            return normalized_path unless localizable?(normalized_path)
            return normalized_path if locale == default_locale
            return "/#{locale}" if normalized_path == '/'

            "/#{locale}#{normalized_path}"
          end
        end
      end
    end
  end
end
