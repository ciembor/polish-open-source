# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Auth
      class DiscordRoleMap
        GLOBAL_KEYS = %w[
          DISCORD_ROLE_TOP_10_PL
          DISCORD_ROLE_TOP_100_PL
          DISCORD_ROLE_BADGE_TOP_1
          DISCORD_ROLE_BADGE_TOP_2
          DISCORD_ROLE_BADGE_TOP_3
        ].freeze

        def role_ids(keys)
          keys.filter_map { |key| ENV.fetch(key, nil) }
        end

        def managed_role_ids
          role_ids(GLOBAL_KEYS + city_role_keys)
        end

        private

        def city_role_keys
          Domain::LocationCatalog.city_slugs.map do |slug|
            "DISCORD_ROLE_TOP_100_CITY_#{slug.upcase.tr('-', '_')}"
          end
        end
      end
    end
  end
end
