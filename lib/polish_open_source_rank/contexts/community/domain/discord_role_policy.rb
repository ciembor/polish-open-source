# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Domain
        # Maps contributor ranking access to Discord role keys.
        class DiscordRolePolicy
          BADGE_ROLE_KEYS = {
            1 => 'DISCORD_ROLE_BADGE_TOP_1',
            2 => 'DISCORD_ROLE_BADGE_TOP_2',
            3 => 'DISCORD_ROLE_BADGE_TOP_3'
          }.freeze

          def initialize(role_catalog: DiscordRoleCatalog.new)
            @role_catalog = role_catalog
          end

          def role_keys(access)
            country_rank = access.fetch(:country_rank)
            city_slug = access.fetch(:city_slug, nil)
            city_rank = access.fetch(:city_rank)
            language_accesses = access.fetch(:language_accesses)

            [].tap do |keys|
              keys << DiscordRoleCatalog::COUNTRY_ROLE_KEY if ranked?(country_rank)
              keys << role_catalog.city_role_key(city_slug) if city_slug && ranked?(city_rank)
              add_language_role_keys(keys, language_accesses)
            end
          end

          def badge_role_key(country_rank)
            BADGE_ROLE_KEYS[country_rank]
          end

          private

          attr_reader :role_catalog

          def ranked?(rank)
            rank && rank <= 100
          end

          def add_language_role_keys(keys, language_accesses)
            language_accesses.each do |language_access|
              language = language_access.fetch(:language)
              keys << DiscordLanguageRoleKey.build_open(language) if language_access.fetch(:member)
              keys << DiscordLanguageRoleKey.build_top(language) if ranked?(language_access[:rank])
            end
          end
        end
      end
    end
  end
end
