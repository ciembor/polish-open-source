# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        LocationMatch = Struct.new(:city, :city_slug, :country, :raw, keyword_init: true) do
          def polish?
            !country.nil?
          end
        end

        class LocationClassifier
          def initialize(catalog = LocationCatalog)
            @catalog = catalog
          end

          def call(location)
            raw = location.to_s.strip
            city = city_for(raw)
            country = country_for(raw, city)

            LocationMatch.new(
              city: city&.fetch(:name),
              city_slug: city&.fetch(:slug),
              country: country,
              raw: raw
            )
          end

          private

          attr_reader :catalog

          def city_for(raw)
            catalog::CITIES.find do |city|
              variant_pattern(city.fetch(:variants)).match?(raw)
            end
          end

          def country_for(raw, city)
            return catalog::COUNTRY if variant_pattern(catalog::COUNTRY_VARIANTS).match?(raw)
            return catalog::COUNTRY if city

            nil
          end

          def variant_pattern(variants)
            Regexp.new("(?:^|[^\\p{L}])(?:#{Regexp.union(variants).source})(?=$|[^\\p{L}])", Regexp::IGNORECASE)
          end
        end
      end
    end
  end
end
