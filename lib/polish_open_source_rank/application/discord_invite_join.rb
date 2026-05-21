# frozen_string_literal: true

module PolishOpenSourceRank
  module Application
    class DiscordInviteJoin
      def initialize(discord_gateway:, discord_role_map:, store: nil, invite_repository: nil,
                     connection_repository: nil, access_read_model: nil)
        @invite_repository = invite_repository || store
        @connection_repository = connection_repository || store
        @access_read_model = access_read_model || store
        @discord_gateway = discord_gateway
        @discord_role_map = discord_role_map
      end

      def call(invite_code:, discord_user_id:, discord_username:)
        profile = find_profile(invite_code)
        return false unless profile

        save_connection(
          platform: profile.fetch(:platform),
          user_github_id: profile.fetch(:github_id),
          discord_user_id: discord_user_id,
          discord_username: discord_username
        )
        access = load_access(profile.fetch(:platform), profile.fetch(:github_id))
        discord_gateway.sync_joined_member(
          discord_user_id: discord_user_id,
          github_login: profile.fetch(:login),
          desired_role_ids: discord_role_map.role_ids(access.fetch(:role_keys)),
          managed_role_ids: discord_role_map.managed_role_ids
        )
        true
      end

      private

      attr_reader :access_read_model, :connection_repository, :discord_gateway, :discord_role_map, :invite_repository

      def find_profile(invite_code)
        if invite_repository.respond_to?(:profile_for_code)
          invite_repository.profile_for_code(invite_code)
        else
          invite_repository.discord_invite_profile(invite_code)
        end
      end

      def save_connection(platform:, user_github_id:, discord_user_id:, discord_username:)
        if connection_repository.respond_to?(:upsert)
          connection_repository.upsert(
            platform: platform,
            user_github_id: user_github_id,
            discord_user_id: discord_user_id,
            discord_username: discord_username
          )
        else
          connection_repository.upsert_discord_connection(
            platform: platform,
            user_github_id: user_github_id,
            discord_user_id: discord_user_id,
            discord_username: discord_username
          )
        end
      end

      def load_access(platform, user_github_id)
        if access_read_model.respond_to?(:access)
          access_read_model.access(platform, user_github_id, period_start: nil)
        else
          access_read_model.discord_access(platform, user_github_id, period_start: nil)
        end
      end
    end
  end
end
