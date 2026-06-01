# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Domain
        # Centralizes Discord role naming so callers only work with ranking concepts.
        class DiscordRoleCatalog
          COUNTRY_ROLE_KEY = 'DISCORD_ROLE_TOP_100_PL'
          CITY_ROLE_PREFIX = 'DISCORD_ROLE_TOP_100_CITY_'
          LANGUAGE_CATEGORY_NAME = 'Languages'
          ROLE_NAME_RESOLVERS = [
            lambda do |_catalog, role_key|
              'Top 100 PL' if role_key == COUNTRY_ROLE_KEY
            end,
            lambda do |catalog, role_key|
              next unless role_key.start_with?(CITY_ROLE_PREFIX)

              "Top 100 #{catalog.send(:city_name, role_key.delete_prefix(CITY_ROLE_PREFIX))}"
            end,
            lambda do |_catalog, role_key|
              DiscordLanguageRoleKey.new(role_key).role_name
            end
          ].freeze

          def initialize(catalog: Contexts::Ranking::Domain::LocationCatalog)
            @catalog = catalog
          end

          def city_role_key(city_slug)
            canonical_slug = catalog.city_slugs.find { |candidate| candidate.casecmp?(city_slug.to_s) } || city_slug
            "DISCORD_ROLE_TOP_100_CITY_#{canonical_slug.to_s.upcase.tr('-', '_')}"
          end

          def role_name(role_key)
            ROLE_NAME_RESOLVERS.lazy.filter_map { |resolver| resolver.call(self, role_key) }.first
          end

          private

          attr_reader :catalog

          def city_name(env_slug)
            slug = env_slug.downcase.tr('_', '-')
            catalog::CITIES.find { |city| city.fetch(:slug) == slug }&.fetch(:name) || env_slug
          end
        end
      end
    end
  end
end
