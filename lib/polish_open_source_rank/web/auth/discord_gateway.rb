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
          update_nickname(discord_user_id, github_login)
          sync_roles(discord_user_id, desired_role_ids, managed_role_ids)
        end

        private

        attr_reader :configuration

        def join_guild(discord_user_id, access_token)
          uri = URI("#{API_BASE}/guilds/#{configuration.discord_guild_id}/members/#{discord_user_id}")
          request = Net::HTTP::Put.new(uri, bot_headers)
          request.body = JSON.generate(access_token: access_token)
          perform_plain(uri, request)
        end

        def update_nickname(discord_user_id, github_login)
          uri = URI("#{API_BASE}/guilds/#{configuration.discord_guild_id}/members/#{discord_user_id}")
          request = Net::HTTP::Patch.new(uri, bot_headers)
          request.body = JSON.generate(nick: github_login)
          perform_plain(uri, request)
        end

        def sync_roles(discord_user_id, desired_role_ids, managed_role_ids)
          (managed_role_ids - desired_role_ids).each { |role_id| remove_role(discord_user_id, role_id) }
          desired_role_ids.each { |role_id| add_role(discord_user_id, role_id) }
        end

        def add_role(discord_user_id, role_id)
          uri = URI("#{API_BASE}/guilds/#{configuration.discord_guild_id}/members/#{discord_user_id}/roles/#{role_id}")
          perform_plain(uri, Net::HTTP::Put.new(uri, bot_headers))
        end

        def remove_role(discord_user_id, role_id)
          uri = URI("#{API_BASE}/guilds/#{configuration.discord_guild_id}/members/#{discord_user_id}/roles/#{role_id}")
          perform_plain(uri, Net::HTTP::Delete.new(uri, bot_headers))
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
