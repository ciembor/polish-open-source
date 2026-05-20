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

            def record(platform:, user_github_id:, code:, url:)
              database.execute(<<~SQL, [platform, user_github_id, code, url, timestamp])
                INSERT INTO discord_invites(platform, user_github_id, code, url, created_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(platform, user_github_id) DO UPDATE SET
                  code = excluded.code,
                  url = excluded.url,
                  created_at = excluded.created_at
              SQL
            end

            def find(platform, user_github_id)
              database.fetch_all(<<~SQL, [platform, user_github_id]).first
                SELECT code, url, created_at
                FROM discord_invites
                WHERE platform = ? AND user_github_id = ?
                LIMIT 1
              SQL
            end

            def profile_for_code(code)
              database.fetch_all(<<~SQL, [code]).first
                SELECT users.platform, users.github_id, users.login
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

            def timestamp
              clock.call.iso8601
            end
          end
        end
      end
    end
  end
end
