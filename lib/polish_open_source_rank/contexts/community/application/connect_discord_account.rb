# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Application
        class ConnectDiscordAccount
          Result = Struct.new(:profile, :access, :role_ids, keyword_init: true)
          class ProfileNotFound < StandardError
          end

          def initialize(profile_read_model:, connection_repository:, access_read_model:, member_gateway:, role_map:)
            @profile_read_model = profile_read_model
            @connection_repository = connection_repository
            @access_read_model = access_read_model
            @member_gateway = member_gateway
            @role_map = role_map
          end

          def call(current_user:, discord_user:, access_token:, period_start:, welcome_channel_id:)
            profile = ranked_profile(current_user, period_start)
            access = access_read_model.discord_access(
              profile.fetch(:platform),
              profile.fetch(:github_id),
              period_start: period_start
            )
            role_ids = role_map.role_ids(access.fetch(:role_keys))

            connect(profile, discord_user)
            sync_member(profile, discord_user, access_token, role_ids)
            post_welcome(welcome_channel_id, profile, discord_user, access, role_ids)

            Result.new(profile: profile, access: access, role_ids: role_ids)
          end

          private

          attr_reader :access_read_model, :connection_repository, :member_gateway, :profile_read_model, :role_map

          def ranked_profile(current_user, period_start)
            profile = profile_read_model.user_profile(
              current_user.fetch(:platform),
              current_user.fetch(:login),
              period_start: period_start
            )
            raise ProfileNotFound unless profile && profile[:period_start]

            profile
          end

          def connect(profile, discord_user)
            connection_repository.upsert_discord_connection(
              platform: profile.fetch(:platform),
              user_github_id: profile.fetch(:github_id),
              discord_user_id: discord_user.fetch('id'),
              discord_username: discord_user['global_name'] || discord_user.fetch('username')
            )
          end

          def sync_member(profile, discord_user, access_token, role_ids)
            member_gateway.sync_member(
              discord_user_id: discord_user.fetch('id'),
              access_token: access_token,
              github_login: profile.fetch(:login),
              desired_role_ids: role_ids,
              managed_role_ids: role_map.managed_role_ids
            )
          end

          def post_welcome(channel_id, profile, discord_user, access, role_ids)
            member_gateway.post_welcome_message(
              channel_id: channel_id,
              discord_user_id: discord_user.fetch('id'),
              profile: profile,
              access: access,
              role_ids: role_ids
            )
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
