# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Domain
        class DiscordRolePolicy
          def role_keys(country_rank:, city_slug:, city_rank:)
            [].tap do |keys|
              add_role_key(keys, 'DISCORD_ROLE_TOP_10_PL', country_rank, 10)
              add_role_key(keys, 'DISCORD_ROLE_TOP_100_PL', country_rank, 100)
              add_role_key(keys, city_role_key(city_slug), city_rank, 100) if city_slug
            end
          end

          def badge_role_key(country_rank)
            case country_rank
            when 1 then 'DISCORD_ROLE_BADGE_TOP_1'
            when 2 then 'DISCORD_ROLE_BADGE_TOP_2'
            when 3 then 'DISCORD_ROLE_BADGE_TOP_3'
            end
          end

          private

          def city_role_key(city_slug)
            "DISCORD_ROLE_TOP_100_CITY_#{city_slug.upcase.tr('-', '_')}"
          end

          def add_role_key(keys, role_key, rank, limit)
            keys << role_key if rank && rank <= limit
          end
        end
      end
    end
  end
end
