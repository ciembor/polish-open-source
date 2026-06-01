# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Infrastructure
        module Discord
          class DiscordApiGateway
            include OAuthHTTP

            class Error < StandardError; end

            API_BASE = 'https://discord.com/api/v10'
            TEXT_CHANNEL_TYPES = [0, 5, 15].freeze
            SEND_MESSAGES = 1 << 11
            VIEW_CHANNEL = 1 << 10

            def initialize(configuration)
              @configuration = configuration
            end

            def create_invite(channel_id:)
              uri = URI("#{API_BASE}/channels/#{channel_id}/invites")
              request = Net::HTTP::Post.new(uri, bot_headers)
              request.body = JSON.generate(max_age: 0, max_uses: 1, unique: true)
              invite = json_request(uri, request)
              code = invite.fetch('code')
              { code: code, url: invite.fetch('url', "https://discord.gg/#{code}") }
            end

            def invite_available?(code)
              uri = URI("#{API_BASE}/invites/#{code}")
              request = Net::HTTP::Get.new(uri)
              response = Net::HTTP.start(uri.host, uri.port, **http_options(uri)) { |http| http.request(request) }
              return false if response.code == '404'
              raise Error, "#{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

              true
            end

            def sync_member(discord_user_id:, access_token:, github_login:, desired_role_ids:, managed_role_ids:)
              join_guild(discord_user_id, access_token)
              sync_joined_member(
                discord_user_id: discord_user_id,
                github_login: github_login,
                desired_role_ids: desired_role_ids,
                managed_role_ids: managed_role_ids
              )
            end

            def post_welcome_message(channel_id:, discord_user_id:, profile:, access:, role_ids:)
              roles = guild_roles
              channels = guild_channels
              payload = DiscordWelcomeMessage.new(
                discord_user_id: discord_user_id,
                profile: profile,
                access: access,
                role_names: role_names(roles, role_ids),
                writable_channels: writable_channels(channels, role_ids)
              ).payload
              create_message(channel_id, payload)
            end

            def sync_joined_member(discord_user_id:, github_login:, desired_role_ids:, managed_role_ids:)
              sync_member_profile(
                discord_user_id,
                nick: github_login,
                role_ids: synced_role_ids(
                  current_role_ids(discord_user_id),
                  desired_role_ids: desired_role_ids,
                  managed_role_ids: managed_role_ids
                )
              )
            end

            attr_reader :configuration

            def join_guild(discord_user_id, access_token)
              uri = URI("#{API_BASE}/guilds/#{configuration.discord_guild_id}/members/#{discord_user_id}")
              request = Net::HTTP::Put.new(uri, bot_headers)
              request.body = JSON.generate(access_token: access_token)
              perform_plain(uri, request)
            end

            def current_role_ids(discord_user_id)
              uri = URI("#{API_BASE}/guilds/#{configuration.discord_guild_id}/members/#{discord_user_id}")
              request = Net::HTTP::Get.new(uri, bot_headers)
              json_request(uri, request).fetch('roles', [])
            end

            def synced_role_ids(current_role_ids, desired_role_ids:, managed_role_ids:)
              current = current_role_ids.uniq
              desired = desired_role_ids.uniq
              managed = managed_role_ids.uniq

              (current - managed + desired).uniq
            end

            def sync_member_profile(discord_user_id, nick:, role_ids:)
              uri = URI("#{API_BASE}/guilds/#{configuration.discord_guild_id}/members/#{discord_user_id}")
              request = Net::HTTP::Patch.new(uri, bot_headers)
              request.body = JSON.generate(nick: nick, roles: role_ids)
              perform_plain(uri, request)
            end

            def guild_roles
              uri = URI("#{API_BASE}/guilds/#{configuration.discord_guild_id}/roles")
              request = Net::HTTP::Get.new(uri, bot_headers)
              json_request(uri, request)
            end

            def guild_channels
              uri = URI("#{API_BASE}/guilds/#{configuration.discord_guild_id}/channels")
              request = Net::HTTP::Get.new(uri, bot_headers)
              json_request(uri, request)
            end

            def create_role(name:, color: nil)
              uri = URI("#{API_BASE}/guilds/#{configuration.discord_guild_id}/roles")
              request = Net::HTTP::Post.new(uri, bot_headers)
              payload = { name: name }
              payload[:color] = color if color
              request.body = JSON.generate(payload)
              json_request(uri, request)
            end

            def create_channel(name:, type:, parent_id: nil, permission_overwrites: nil)
              uri = URI("#{API_BASE}/guilds/#{configuration.discord_guild_id}/channels")
              request = Net::HTTP::Post.new(uri, bot_headers)
              payload = { name: name, type: type }
              payload[:parent_id] = parent_id if parent_id
              payload[:permission_overwrites] = permission_overwrites if permission_overwrites
              request.body = JSON.generate(payload)
              json_request(uri, request)
            end

            def create_message(channel_id, payload)
              uri = URI("#{API_BASE}/channels/#{channel_id}/messages")
              request = Net::HTTP::Post.new(uri, bot_headers)
              request.body = JSON.generate(payload)
              json_request(uri, request)
            end

            def role_names(roles, role_ids)
              names_by_id = roles.to_h { |role| [role.fetch('id'), role.fetch('name')] }
              role_ids.filter_map { |role_id| names_by_id[role_id] }
            end

            def writable_channels(channels, role_ids)
              channels_by_id = channels.to_h { |channel| [channel.fetch('id'), channel] }
              channels
                .select { |channel| writable_text_channel?(channel, channels_by_id, role_ids) }
                .sort_by { |channel| [channel.fetch('position', 0), channel.fetch('name')] }
                .map { |channel| "<##{channel.fetch('id')}>" }
            end

            def writable_text_channel?(channel, channels_by_id, role_ids)
              return false unless TEXT_CHANNEL_TYPES.include?(channel.fetch('type'))

              effective_overwrites(channel, channels_by_id).any? do |overwrite|
                overwrite.fetch('type').zero? &&
                  role_ids.include?(overwrite.fetch('id')) &&
                  permission_allowed?(overwrite, SEND_MESSAGES)
              end
            end

            def effective_overwrites(channel, channels_by_id)
              parent = channels_by_id[channel['parent_id']]
              Array(parent&.fetch('permission_overwrites', [])) + Array(channel.fetch('permission_overwrites', []))
            end

            def permission_allowed?(overwrite, permission)
              allow = overwrite.fetch('allow').to_i
              deny = overwrite.fetch('deny').to_i

              allow.anybits?(permission) && deny.nobits?(permission)
            end

            def private_channel_overwrites(role_id)
              allowed = (VIEW_CHANNEL | SEND_MESSAGES).to_s
              denied = (VIEW_CHANNEL | SEND_MESSAGES).to_s
              [
                { id: configuration.discord_guild_id, type: 0, allow: '0', deny: denied },
                { id: role_id, type: 0, allow: allowed, deny: '0' }
              ]
            end

            private

            def bot_headers
              {
                'Authorization' => "Bot #{configuration.discord_bot_token}",
                'Content-Type' => 'application/json'
              }
            end
          end
        end
      end
    end
  end
end
