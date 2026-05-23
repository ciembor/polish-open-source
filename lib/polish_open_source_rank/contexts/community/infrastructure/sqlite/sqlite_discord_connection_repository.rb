# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Infrastructure
        module SQLite
          class SQLiteDiscordConnectionRepository
            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def upsert(platform:, source_id:, discord_user_id:, discord_username:)
              attributes = {
                platform: platform,
                user_github_id: source_id,
                discord_user_id: discord_user_id,
                discord_username: discord_username,
                updated_at: timestamp
              }
              scoped = connections_dataset.where(platform: platform, user_github_id: source_id)

              database.transaction do
                next unless scoped.update(update_attributes(attributes)).zero?

                connections_dataset.insert(attributes)
              end
            rescue Sequel::UniqueConstraintViolation
              scoped.update(update_attributes(attributes))
            end

            def upsert_discord_connection(platform:, source_id:, discord_user_id:, discord_username:)
              upsert(
                platform: platform,
                source_id: source_id,
                discord_user_id: discord_user_id,
                discord_username: discord_username
              )
            end

            def find(platform, source_id)
              database.fetch_all(<<~SQL, [platform, source_id]).first
                SELECT discord_user_id, discord_username, updated_at
                FROM discord_connections
                WHERE platform = ? AND user_github_id = ?
                LIMIT 1
              SQL
            end

            def discord_connection(platform, source_id)
              find(platform, source_id)
            end

            private

            attr_reader :clock, :database

            def connections_dataset
              database.dataset(:discord_connections)
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
