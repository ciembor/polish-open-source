# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Infrastructure
        module SQLite
          class SQLiteManualDiscordInviteRepository
            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def record(profile:, invite:, invited_by:)
              attributes = invite_attributes(profile: profile, invite: invite, invited_by: invited_by)
              database.transaction do
                upsert_user(profile)
                upsert_invite(attributes)
              end
              attributes
            end

            def invited?(platform, source_id)
              !database.fetch_all(<<~SQL, [platform, source_id]).empty?
                SELECT 1
                FROM manual_discord_invites
                WHERE platform = ? AND user_github_id = ? AND revoked_at IS NULL
                LIMIT 1
              SQL
            end

            def active_invites
              database.fetch_all(<<~SQL)
                SELECT platform, user_github_id AS source_id, login, code, url, invited_by, created_at
                FROM manual_discord_invites
                WHERE revoked_at IS NULL
                ORDER BY created_at DESC, login COLLATE NOCASE ASC
              SQL
            end

            private

            attr_reader :clock, :database

            def upsert_user(profile)
              attributes = user_attributes(profile)
              scoped = users_dataset.where(platform: profile.fetch(:platform), github_id: profile.fetch(:source_id))
              return if scoped.update(attributes.except(:platform, :github_id)).positive?

              users_dataset.insert(attributes)
            rescue Sequel::UniqueConstraintViolation
              users_dataset.where(platform: profile.fetch(:platform), login: profile.fetch(:login))
                           .update(attributes.except(:platform, :github_id, :login))
            end

            def upsert_invite(attributes)
              scoped = invites_dataset.where(
                platform: attributes.fetch(:platform),
                user_github_id: attributes.fetch(:user_github_id)
              )
              return if scoped.update(attributes.except(:platform, :user_github_id)).positive?

              invites_dataset.insert(attributes)
            rescue Sequel::UniqueConstraintViolation
              invites_dataset.where(platform: attributes.fetch(:platform), login: attributes.fetch(:login))
                             .update(attributes.except(:platform, :user_github_id, :login))
            end

            def user_attributes(profile)
              {
                platform: profile.fetch(:platform),
                github_id: profile.fetch(:source_id),
                login: profile.fetch(:login),
                name: profile[:name],
                location_raw: profile[:location],
                city: nil,
                country: nil,
                email: profile[:email],
                homepage: profile[:homepage],
                html_url: profile.fetch(:html_url),
                avatar_url: profile[:avatar_url],
                updated_at: timestamp
              }
            end

            def invite_attributes(profile:, invite:, invited_by:)
              {
                platform: profile.fetch(:platform),
                user_github_id: profile.fetch(:source_id),
                login: profile.fetch(:login),
                code: invite.fetch(:code),
                url: invite.fetch(:url),
                invited_by: invited_by,
                created_at: timestamp,
                revoked_at: nil
              }
            end

            def users_dataset
              database.dataset(:users)
            end

            def invites_dataset
              database.dataset(:manual_discord_invites)
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
