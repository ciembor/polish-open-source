# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Application
        class SyncDiscordConnection
          MAX_ATTEMPTS = 3

          def initialize(sync_job_repository:, profile_read_model:, access_read_model:, member_gateway:, role_map:)
            @sync_job_repository = sync_job_repository
            @profile_read_model = profile_read_model
            @access_read_model = access_read_model
            @member_gateway = member_gateway
            @role_map = role_map
          end

          def call(period_start:, limit: 10)
            sync_job_repository.pending(limit: limit).each do |job|
              sync_job(job, period_start)
            end
          end

          private

          attr_reader :access_read_model, :member_gateway, :profile_read_model, :role_map, :sync_job_repository

          def sync_job(job, period_start)
            case job.fetch(:action_kind)
            when 'member_sync'
              sync_member(job, period_start)
            when 'welcome_message'
              post_welcome(job, period_start)
            end
            sync_job_repository.mark_synced(job)
          rescue StandardError => e
            record_failure(job, e)
          end

          def sync_member(job, period_start)
            access = access(job, period_start)
            role_ids = role_map.role_ids(access.fetch(:role_keys))
            if job[:access_token]
              member_gateway.sync_member(
                discord_user_id: job.fetch(:discord_user_id),
                access_token: job.fetch(:access_token),
                github_login: job.fetch(:login),
                desired_role_ids: role_ids,
                managed_role_ids: role_map.managed_role_ids
              )
            else
              member_gateway.sync_joined_member(
                discord_user_id: job.fetch(:discord_user_id),
                github_login: job.fetch(:login),
                desired_role_ids: role_ids,
                managed_role_ids: role_map.managed_role_ids
              )
            end
          end

          def post_welcome(job, period_start)
            profile = profile_read_model.user_profile(
              job.fetch(:platform),
              job.fetch(:login),
              period_start: period_start
            )
            access = access(job, period_start)
            member_gateway.post_welcome_message(
              channel_id: job.fetch(:welcome_channel_id),
              discord_user_id: job.fetch(:discord_user_id),
              profile: profile,
              access: access,
              role_ids: role_map.role_ids(access.fetch(:role_keys))
            )
          end

          def access(job, period_start)
            access_read_model.discord_access(
              job.fetch(:platform),
              job.fetch(:source_id),
              period_start: period_start
            )
          end

          def record_failure(job, error)
            if job.fetch(:attempts).to_i + 1 >= MAX_ATTEMPTS
              sync_job_repository.mark_failed(job, error)
            else
              sync_job_repository.mark_retryable(job, error)
            end
          end
        end
      end
    end
  end
end
