# frozen_string_literal: true

require 'yaml'

module PolishOpenSourceRank
  module Web
    module Localization
      class TranslationCatalog
        def self.load(root:, locales:)
          translations = locales.to_h do |locale|
            path = root.join("config/locales/#{locale}.yml")
            [locale, flatten(YAML.load_file(path).fetch(locale))]
          end
          new(translations)
        end

        def self.flatten(values, prefix = nil)
          values.each_with_object({}) do |(key, value), result|
            full_key = [prefix, key].compact.join('.')
            value.is_a?(Hash) ? result.merge!(flatten(value, full_key)) : result[full_key] = value
          end
        end

        def initialize(translations)
          @translations = translations.freeze
        end

        def translate(locale, key, values = {})
          values.reduce(@translations.fetch(locale).fetch(key)) do |text, (name, value)|
            text.gsub("%{#{name}}", value.to_s)
          end
        end
      end
    end
  end
end
