# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Application
        class ShowDiscordPanel
          Panel = Struct.new(:connection, :access, :access_channels, keyword_init: true) do
            def fetch(key, *fallback, &)
              to_h.fetch(key, *fallback, &)
            end
          end

          def initialize(connection_repository:, access_read_model:, catalog: Contexts::Ranking::Domain::LocationCatalog)
            @connection_repository = connection_repository
            @access_read_model = access_read_model
            @catalog = catalog
          end

          def call(platform:, source_id:, period_start:)
            access = access_read_model.discord_access(platform, source_id, period_start: period_start)
            Panel.new(
              connection: connection_repository.discord_connection(platform, source_id),
              access: access,
              access_channels: access_channels(access.fetch(:role_keys))
            )
          end

          private

          attr_reader :access_read_model, :catalog, :connection_repository

          def access_channels(role_keys)
            ['general'] + role_keys.filter_map do |role_key|
              case role_key
              when 'DISCORD_ROLE_TOP_10_PL' then 'Top 10 PL'
              when 'DISCORD_ROLE_TOP_100_PL' then 'Top 100 PL'
              when /\ADISCORD_ROLE_TOP_100_CITY_(.+)\z/
                "Top 100 #{city_name(Regexp.last_match(1))}"
              end
            end
          end

          def city_name(env_slug)
            slug = env_slug.downcase.tr('_', '-')
            catalog::CITIES.find { |city| city.fetch(:slug) == slug }&.fetch(:name) || env_slug
          end
        end
      end
    end
  end
end
