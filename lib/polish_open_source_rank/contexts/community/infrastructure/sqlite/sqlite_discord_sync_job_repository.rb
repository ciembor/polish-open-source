# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Infrastructure
        module SQLite
          class SQLiteDiscordSyncJobRepository
            MEMBER_SYNC = 'member_sync'
            WELCOME_MESSAGE = 'welcome_message'
            ACTIVE_STATUSES = %w[pending retryable].freeze

            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def request_oauth_sync(platform:, source_id:, discord_user_id:, discord_username:, access_token:,
                                   welcome_channel_id:)
              database.transaction do
                upsert_job(member_sync_attributes(platform, source_id, discord_user_id, discord_username, access_token))
                upsert_welcome_job(platform, source_id, discord_user_id, discord_username, welcome_channel_id)
              end
            end

            def request_invite_sync(platform:, source_id:, discord_user_id:, discord_username:)
              database.transaction do
                upsert_job(member_sync_attributes(platform, source_id, discord_user_id, discord_username))
              end
            end

            def sync_status(platform, source_id)
              rows = database.fetch_all(<<~SQL, [platform, source_id])
                SELECT status
                FROM discord_sync_jobs
                WHERE platform = ? AND user_github_id = ?
              SQL
              statuses = rows.map { |row| row.fetch(:status) }
              return nil if statuses.empty?
              return 'failed' if statuses.include?('failed')
              return 'retryable' if statuses.include?('retryable')
              return 'pending' if statuses.include?('pending')

              'synced'
            end

            def pending(limit: 10)
              database.fetch_all(<<~SQL, [limit])
                SELECT #{pending_columns_sql}
                FROM discord_sync_jobs
                JOIN users
                  ON users.platform = discord_sync_jobs.platform
                 AND users.github_id = discord_sync_jobs.user_github_id
                WHERE discord_sync_jobs.status IN ('pending', 'retryable')
                ORDER BY discord_sync_jobs.updated_at ASC
                LIMIT ?
              SQL
            end

            def pending_for(platform, source_id)
              database.fetch_all(<<~SQL, [platform, source_id])
                SELECT #{pending_columns_sql}
                FROM discord_sync_jobs
                JOIN users
                  ON users.platform = discord_sync_jobs.platform
                 AND users.github_id = discord_sync_jobs.user_github_id
                WHERE discord_sync_jobs.platform = ?
                  AND discord_sync_jobs.user_github_id = ?
                  AND discord_sync_jobs.status IN ('pending', 'retryable')
                ORDER BY discord_sync_jobs.updated_at ASC
              SQL
            end

            def mark_synced(job)
              update_status(job, terminal_status_attributes(status: 'synced', error: nil, synced_at: timestamp))
            end

            def mark_retryable(job, error)
              update_status(job, status: 'retryable', error: error.message, attempts: job.fetch(:attempts).to_i + 1)
            end

            def mark_failed(job, error)
              attempts = job.fetch(:attempts).to_i + 1
              update_status(
                job,
                terminal_status_attributes(status: 'failed', error: error.message, attempts: attempts)
              )
            end

            private

            attr_reader :clock, :database

            def pending_columns_sql
              [
                'discord_sync_jobs.platform',
                'discord_sync_jobs.user_github_id AS source_id',
                'discord_sync_jobs.action_kind',
                'discord_sync_jobs.discord_user_id',
                'discord_sync_jobs.discord_username',
                'discord_sync_jobs.access_token',
                'discord_sync_jobs.welcome_channel_id',
                'discord_sync_jobs.status',
                'discord_sync_jobs.attempts',
                'discord_sync_jobs.error',
                'discord_sync_jobs.created_at',
                'discord_sync_jobs.updated_at',
                'discord_sync_jobs.synced_at',
                'users.login'
              ].join(', ')
            end

            def member_sync_attributes(platform, source_id, discord_user_id, discord_username, access_token = nil)
              job_attributes(
                platform: platform,
                source_id: source_id,
                action_kind: MEMBER_SYNC,
                discord_user_id: discord_user_id,
                discord_username: discord_username,
                access_token: access_token
              )
            end

            def welcome_attributes(platform, source_id, discord_user_id, discord_username, welcome_channel_id)
              job_attributes(
                platform: platform,
                source_id: source_id,
                action_kind: WELCOME_MESSAGE,
                discord_user_id: discord_user_id,
                discord_username: discord_username,
                welcome_channel_id: welcome_channel_id
              )
            end

            def upsert_welcome_job(platform, source_id, discord_user_id, discord_username, welcome_channel_id)
              return if welcome_channel_id.to_s.strip.empty?

              upsert_job(welcome_attributes(platform, source_id, discord_user_id, discord_username, welcome_channel_id))
            end

            def job_attributes(attributes)
              {
                platform: attributes.fetch(:platform),
                user_github_id: attributes.fetch(:source_id),
                action_kind: attributes.fetch(:action_kind),
                discord_user_id: attributes.fetch(:discord_user_id),
                discord_username: attributes.fetch(:discord_username),
                access_token: attributes.fetch(:access_token, nil),
                welcome_channel_id: attributes.fetch(:welcome_channel_id, nil),
                status: 'pending',
                attempts: 0,
                error: nil,
                created_at: timestamp,
                updated_at: timestamp,
                synced_at: nil
              }
            end

            def upsert_job(attributes)
              scoped = jobs_dataset.where(
                platform: attributes.fetch(:platform),
                user_github_id: attributes.fetch(:user_github_id),
                action_kind: attributes.fetch(:action_kind)
              )

              return if scoped.update(update_attributes(attributes)).positive?

              jobs_dataset.insert(attributes)
            rescue Sequel::UniqueConstraintViolation
              scoped.update(update_attributes(attributes))
            end

            def update_status(job, attributes)
              scoped_job(job).update(attributes.merge(updated_at: timestamp))
            end

            def terminal_status_attributes(attributes)
              attributes.merge(access_token: nil)
            end

            def scoped_job(job)
              jobs_dataset.where(
                platform: job.fetch(:platform),
                user_github_id: job.fetch(:source_id),
                action_kind: job.fetch(:action_kind)
              )
            end

            def jobs_dataset
              database.dataset(:discord_sync_jobs)
            end

            def update_attributes(attributes)
              attributes.except(:platform, :user_github_id, :action_kind, :created_at)
            end

            def timestamp
              clock.call.iso8601
            end
          end
        end
      end
    end
  end
end
