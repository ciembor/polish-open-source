# frozen_string_literal: true

require_relative 'oauth_http'

module PolishOpenSourceRank
  module Web
    module Auth
      class DiscordGateway
        include OAuthHTTP

        class Error < StandardError; end

        API_BASE = 'https://discord.com/api/v10'

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
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
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

        private

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
