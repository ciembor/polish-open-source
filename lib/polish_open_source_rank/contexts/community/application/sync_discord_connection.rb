# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Application
        # Drains pending Discord sync jobs against one prepared ranking snapshot.
        class SyncDiscordConnection
          MAX_ATTEMPTS = 3
          # Bundles immutable inputs shared across one prepared sync pass.
          SyncContext = Struct.new(:job, :period_start, :prepared_roles, keyword_init: true)

          def initialize(sync_job_repository:, profile_read_model:, access_read_model:, member_gateway:, role_map:)
            @sync_job_repository = sync_job_repository
            @profile_read_model = profile_read_model
            @access_read_model = access_read_model
            @member_gateway = member_gateway
            @role_map = role_map
          end

          def call(period_start:, limit: 10)
            prepared_roles = role_map.prepare(period_start: period_start)
            sync_job_repository.pending(limit: limit).each do |job|
              sync_job(SyncContext.new(job: job, period_start: period_start, prepared_roles: prepared_roles))
            end
          end

          private

          attr_reader :access_read_model, :member_gateway, :profile_read_model, :role_map, :sync_job_repository

          def sync_job(context)
            job = context.job
            case job.fetch(:action_kind)
            when 'member_sync'
              sync_member(context)
            when 'welcome_message'
              post_welcome(context)
            end
            sync_job_repository.mark_synced(job)
          rescue StandardError => e
            record_failure(job, e)
          end

          def sync_member(context)
            job = context.job
            prepared_roles = context.prepared_roles
            access = access(job, context.period_start)
            member_payload = member_payload(job, prepared_roles, access)
            return member_gateway.sync_joined_member(**member_payload) unless job[:access_token]

            member_gateway.sync_member(**member_payload, access_token: job.fetch(:access_token))
          end

          def post_welcome(context)
            job = context.job
            platform = job.fetch(:platform)
            login = job.fetch(:login)
            discord_user_id = job.fetch(:discord_user_id)
            welcome_channel_id = job.fetch(:welcome_channel_id)
            access = access(job, context.period_start)

            profile = profile_read_model.user_profile(
              platform,
              login,
              period_start: context.period_start
            )
            member_gateway.post_welcome_message(
              channel_id: welcome_channel_id,
              discord_user_id: discord_user_id,
              profile: profile,
              access: access,
              role_ids: context.prepared_roles.role_ids(access.fetch(:role_keys))
            )
          end

          def access(job, period_start)
            access_read_model.discord_access(
              job.fetch(:platform),
              job.fetch(:source_id),
              period_start: period_start
            )
          end

          def member_payload(job, prepared_roles, access)
            {
              discord_user_id: job.fetch(:discord_user_id),
              github_login: job.fetch(:login),
              desired_role_ids: prepared_roles.role_ids(access.fetch(:role_keys)),
              managed_role_ids: role_map.managed_role_ids(prepared: prepared_roles)
            }
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
