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

            def upsert(platform:, user_github_id:, discord_user_id:, discord_username:)
              database.execute(<<~SQL, [platform, user_github_id, discord_user_id, discord_username, timestamp])
                INSERT INTO discord_connections(
                  platform, user_github_id, discord_user_id, discord_username, updated_at
                )
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(platform, user_github_id) DO UPDATE SET
                  discord_user_id = excluded.discord_user_id,
                  discord_username = excluded.discord_username,
                  updated_at = excluded.updated_at
              SQL
            end

            def upsert_discord_connection(platform:, user_github_id:, discord_user_id:, discord_username:)
              upsert(
                platform: platform,
                user_github_id: user_github_id,
                discord_user_id: discord_user_id,
                discord_username: discord_username
              )
            end

            def find(platform, user_github_id)
              database.fetch_all(<<~SQL, [platform, user_github_id]).first
                SELECT discord_user_id, discord_username, updated_at
                FROM discord_connections
                WHERE platform = ? AND user_github_id = ?
                LIMIT 1
              SQL
            end

            def discord_connection(platform, user_github_id)
              find(platform, user_github_id)
            end

            private

            attr_reader :clock, :database

            def timestamp
              clock.call.iso8601
            end
          end
        end
      end
    end
  end
end
