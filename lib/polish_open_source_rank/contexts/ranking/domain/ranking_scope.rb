# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        class RankingScope
          POLAND = 'poland'

          attr_reader :slug

          def initialize(slug)
            @slug = slug.to_s
            return if @slug == POLAND || LocationCatalog.city_slugs.include?(@slug)

            raise ArgumentError, "Unsupported ranking scope: #{slug.inspect}"
          end

          def self.poland
            new(POLAND)
          end

          def country?
            slug == POLAND
          end

          def city_name
            LocationCatalog.city_name(slug) unless country?
          end
        end
      end
    end
  end
end
