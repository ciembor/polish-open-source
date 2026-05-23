# frozen_string_literal: true

module PolishOpenSourceRank
  module Application
    class DiscordInviteJoin
      def initialize(
        discord_gateway:,
        discord_role_map:,
        invite_repository:,
        connection_repository:,
        access_read_model:
      )
        @invite_repository = invite_repository
        @connection_repository = connection_repository
        @access_read_model = access_read_model
        @discord_gateway = discord_gateway
        @discord_role_map = discord_role_map
      end

      def call(invite_code:, discord_user_id:, discord_username:)
        profile = find_profile(invite_code)
        return false unless profile

        save_connection(
          platform: profile.fetch(:platform),
          source_id: profile.fetch(:source_id),
          discord_user_id: discord_user_id,
          discord_username: discord_username
        )
        access = load_access(profile.fetch(:platform), profile.fetch(:source_id))
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
        invite_repository.profile_for_code(invite_code)
      end

      def save_connection(platform:, source_id:, discord_user_id:, discord_username:)
        connection_repository.upsert(
          platform: platform,
          source_id: source_id,
          discord_user_id: discord_user_id,
          discord_username: discord_username
        )
      end

      def load_access(platform, source_id)
        access_read_model.access(platform, source_id, period_start: nil)
      end
    end
  end
end
