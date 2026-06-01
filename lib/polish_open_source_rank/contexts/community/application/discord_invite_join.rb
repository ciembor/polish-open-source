# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Application
        class DiscordInviteJoin
          def initialize(
            invite_repository:,
            connection_repository:,
            sync_job_repository:
          )
            @invite_repository = invite_repository
            @connection_repository = connection_repository
            @sync_job_repository = sync_job_repository
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
            sync_job_repository.request_invite_sync(
              platform: profile.fetch(:platform),
              source_id: profile.fetch(:source_id),
              discord_user_id: discord_user_id,
              discord_username: discord_username
            )
            true
          end

          private

          attr_reader :connection_repository, :invite_repository, :sync_job_repository

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
        end
      end
    end
  end
end
