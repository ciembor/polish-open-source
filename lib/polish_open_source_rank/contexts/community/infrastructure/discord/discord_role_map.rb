# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Infrastructure
        module Discord
          # Resolves configured Discord roles and provisions dynamic language roles on demand.
          class DiscordRoleMap
            # Captures one prepared role snapshot so callers don't re-resolve dynamic ids.
            class PreparedRoles
              attr_reader :managed_role_ids, :role_ids_by_key

              def initialize(managed_role_ids:, role_ids_by_key:)
                @managed_role_ids = managed_role_ids
                @role_ids_by_key = role_ids_by_key
              end

              def role_ids(keys)
                keys.filter_map { |key| role_ids_by_key.fetch(key, nil) || ENV.fetch(key, nil) }
              end
            end

            # Mutable provisioning snapshot used while ensuring dynamic roles and channels.
            ProvisioningState = Struct.new(
              :roles,
              :channels,
              :category_id,
              :channel_creation_disabled,
              :role_creation_disabled,
              keyword_init: true
            )

            GLOBAL_KEYS = %w[
              DISCORD_ROLE_TOP_100_PL
              DISCORD_ROLE_BADGE_TOP_1
              DISCORD_ROLE_BADGE_TOP_2
              DISCORD_ROLE_BADGE_TOP_3
            ].freeze

            def initialize(gateway: nil, published_language_source: nil,
                           role_catalog: Contexts::Community::Domain::DiscordRoleCatalog.new)
              @gateway = gateway
              @published_language_source = published_language_source
              @role_catalog = role_catalog
            end

            def prepare(period_start:, role_keys: nil)
              static_role_ids = static_role_ids(GLOBAL_KEYS + city_role_keys)
              return PreparedRoles.new(managed_role_ids: static_role_ids, role_ids_by_key: {}) unless gateway

              dynamic_role_keys = dynamic_role_keys(period_start, role_keys)
              if dynamic_role_keys.empty?
                return PreparedRoles.new(managed_role_ids: static_role_ids, role_ids_by_key: {})
              end

              state = provisioning_state
              ensure_language_resources(dynamic_role_keys, state)

              build_prepared_roles(static_role_ids, dynamic_role_ids_by_key(dynamic_role_keys, state.roles))
            end

            def managed_role_ids(prepared: nil)
              return prepared.managed_role_ids if prepared

              static_role_ids(GLOBAL_KEYS + city_role_keys)
            end

            def role_ids(keys, prepared: nil)
              prepared ? prepared.role_ids(keys) : static_role_ids(keys)
            end

            private

            attr_reader :gateway, :published_language_source, :role_catalog

            def city_role_keys
              Contexts::Ranking::Domain::LocationCatalog.city_slugs.map do |slug|
                "DISCORD_ROLE_TOP_100_CITY_#{slug.upcase.tr('-', '_')}"
              end
            end

            def static_role_ids(keys)
              keys.filter_map { |key| ENV.fetch(key, nil) }
            end

            def published_languages(period_start)
              return [] unless published_language_source

              published_language_source.published_languages(period_start: period_start)
            end

            def provisioning_state
              channels = gateway.guild_channels
              ProvisioningState.new(
                roles: gateway.guild_roles,
                channels: channels,
                category_id: ensure_category_id(channels),
                channel_creation_disabled: false,
                role_creation_disabled: false
              )
            end

            def build_prepared_roles(static_role_ids, role_ids_by_key)
              PreparedRoles.new(
                managed_role_ids: (static_role_ids + role_ids_by_key.values).uniq,
                role_ids_by_key: role_ids_by_key
              )
            end

            def dynamic_role_keys(period_start, role_keys)
              return role_keys.filter { |key| Domain::DiscordLanguageRoleKey.new(key).dynamic? }.uniq if role_keys

              language_role_keys(published_languages(period_start))
            end

            def ensure_language_resources(role_keys, state)
              role_keys.each { |role_key| ensure_language_role_and_channel(role_key, state) }
            end

            def ensure_language_role_and_channel(role_key, state)
              role = ensure_dynamic_role(role_key, state)
              return unless role

              ensure_dynamic_channel(role_key, role.fetch('id'), state)
            end

            def ensure_category_id(channels)
              category_name = Contexts::Community::Domain::DiscordRoleCatalog::LANGUAGE_CATEGORY_NAME
              category = channels.find do |channel|
                channel.fetch('type') == 4 && channel.fetch('name') == category_name
              end
              return category.fetch('id') if category

              category = gateway.create_channel(name: category_name, type: 4)
              channels << category
              category.fetch('id')
            end

            def ensure_dynamic_role(role_key, state)
              return if state.role_creation_disabled

              roles = state.roles
              role_name = role_catalog.role_name(role_key)
              role = roles.find { |candidate| candidate.fetch('name') == role_name }
              return role if role

              role = gateway.create_role(name: role_name, color: Domain::DiscordLanguageRoleKey.new(role_key).role_color)
              roles << role
              role
            rescue DiscordApiGateway::Error => e
              raise unless server_role_limit?(e)

              state.role_creation_disabled = true
              nil
            end

            def ensure_dynamic_channel(role_key, role_id, state)
              return if state.channel_creation_disabled

              channel_name = Domain::DiscordLanguageRoleKey.new(role_key).channel_name
              return unless channel_name

              channels = state.channels
              return if channels.any? { |channel| channel.fetch('name') == channel_name }

              channel = gateway.create_channel(
                name: channel_name,
                type: 0,
                parent_id: state.category_id,
                permission_overwrites: gateway.private_channel_overwrites(role_id)
              )
              channels << channel
            rescue DiscordApiGateway::Error => e
              raise unless category_channel_limit?(e)

              state.channel_creation_disabled = true
            end

            def dynamic_role_ids_by_key(role_keys, roles)
              roles_by_name = roles.to_h { |role| [role.fetch('name'), role.fetch('id')] }
              role_keys.to_h do |key|
                [key, roles_by_name[role_catalog.role_name(key)]]
              end.compact
            end

            def language_role_keys(languages)
              languages.flat_map do |language|
                [Domain::DiscordLanguageRoleKey.build_open(language), Domain::DiscordLanguageRoleKey.build_top(language)]
              end
            end

            def category_channel_limit?(error)
              error.message.include?('CHANNEL_PARENT_MAX_CHANNELS')
            end

            def server_role_limit?(error)
              error.message.include?('"code": 30005') || error.message.include?('Maximum number of server roles')
            end
          end
        end
      end
    end
  end
end
