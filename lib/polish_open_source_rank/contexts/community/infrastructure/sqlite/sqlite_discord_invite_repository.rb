# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Infrastructure
        module SQLite
          class SQLiteDiscordInviteRepository
            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def record(platform:, source_id:, code:, url:)
              attributes = {
                platform: platform,
                user_github_id: source_id,
                code: code,
                url: url,
                created_at: timestamp
              }
              scoped = invites_dataset.where(platform: platform, user_github_id: source_id)

              database.transaction do
                next unless scoped.update(update_attributes(attributes)).zero?

                invites_dataset.insert(attributes)
              end
            rescue Sequel::UniqueConstraintViolation
              database.write { scoped.update(update_attributes(attributes)) }
            end

            def find(platform, source_id)
              database.fetch_all(<<~SQL, [platform, source_id]).first
                SELECT code, url, created_at
                FROM discord_invites
                WHERE platform = ? AND user_github_id = ?
                LIMIT 1
              SQL
            end

            def profile_for_code(code)
              database.fetch_all(<<~SQL, [code]).first
                SELECT users.platform, users.github_id AS source_id, users.login
                FROM discord_invites
                JOIN users
                  ON users.platform = discord_invites.platform
                 AND users.github_id = discord_invites.user_github_id
                WHERE discord_invites.code = ?
                LIMIT 1
              SQL
            end

            private

            attr_reader :clock, :database

            def invites_dataset
              database.dataset(:discord_invites)
            end

            def update_attributes(attributes)
              attributes.except(:platform, :user_github_id)
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
