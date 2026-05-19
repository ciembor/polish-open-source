# frozen_string_literal: true

module PolishOpenSourceRank
  module Application
    class DiscordInviteJoin
      def initialize(store:, discord_gateway:, discord_role_map:)
        @store = store
        @discord_gateway = discord_gateway
        @discord_role_map = discord_role_map
      end

      def call(invite_code:, discord_user_id:, discord_username:)
        profile = store.discord_invite_profile(invite_code)
        return false unless profile

        store.upsert_discord_connection(
          platform: profile.fetch(:platform),
          user_github_id: profile.fetch(:github_id),
          discord_user_id: discord_user_id,
          discord_username: discord_username
        )
        access = store.discord_access(profile.fetch(:platform), profile.fetch(:github_id))
        discord_gateway.sync_joined_member(
          discord_user_id: discord_user_id,
          github_login: profile.fetch(:login),
          desired_role_ids: discord_role_map.role_ids(access.fetch(:role_keys)),
          managed_role_ids: discord_role_map.managed_role_ids
        )
        true
      end

      private

      attr_reader :store, :discord_gateway, :discord_role_map
    end
  end
end
