# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Application
        class ConnectDiscordAccount
          Result = Struct.new(:profile, :access, :role_ids, :sync_status, keyword_init: true)
          class PublicProfileNotFound < StandardError
          end

          def initialize(profile_read_model:, connection_repository:, sync_job_repository:, access_read_model:,
                         role_map:)
            @profile_read_model = profile_read_model
            @connection_repository = connection_repository
            @sync_job_repository = sync_job_repository
            @access_read_model = access_read_model
            @role_map = role_map
          end

          def call(current_user:, discord_user:, access_token:, period_start:, welcome_channel_id:)
            profile = public_profile(current_user, period_start)
            access = access_read_model.discord_access(
              profile.fetch(:platform),
              profile.fetch(:source_id),
              period_start: period_start
            )
            role_ids = role_map.role_ids(access.fetch(:role_keys))

            connect(profile, discord_user)
            request_sync(profile, discord_user, access_token, welcome_channel_id)

            Result.new(profile: profile, access: access, role_ids: role_ids, sync_status: 'pending')
          end

          private

          attr_reader :access_read_model, :connection_repository, :profile_read_model, :role_map, :sync_job_repository

          def public_profile(current_user, period_start)
            profile = profile_read_model.user_profile(
              current_user.fetch(:platform),
              current_user.fetch(:login),
              period_start: period_start
            )
            raise PublicProfileNotFound unless profile

            profile
          end

          def connect(profile, discord_user)
            connection_repository.upsert_discord_connection(
              platform: profile.fetch(:platform),
              source_id: profile.fetch(:source_id),
              discord_user_id: discord_user.fetch('id'),
              discord_username: discord_username(discord_user)
            )
          end

          def discord_username(discord_user)
            discord_user['global_name'] || discord_user.fetch('username')
          end

          def request_sync(profile, discord_user, access_token, welcome_channel_id)
            sync_job_repository.request_oauth_sync(
              platform: profile.fetch(:platform),
              source_id: profile.fetch(:source_id),
              discord_user_id: discord_user.fetch('id'),
              discord_username: discord_username(discord_user),
              access_token: access_token,
              welcome_channel_id: welcome_channel_id
            )
          end
        end
      end
    end
  end
end
