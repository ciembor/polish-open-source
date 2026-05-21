# frozen_string_literal: true

require 'discordrb'

module PolishOpenSourceRank
  module Contexts
    module Community
      module Infrastructure
        module Discord
          class DiscordInviteBot
            def self.build(configuration:, logger: $stdout, store: nil)
              invite_repository, connection_repository, access_read_model =
                store ? repositories_from_store(store) : repositories_from_database(configuration)

              new(
                guild_id: configuration.discord_guild_id,
                bot: Discordrb::Bot.new(token: configuration.discord_bot_token, intents: %i[server_invites]),
                join_handler: PolishOpenSourceRank::Application::DiscordInviteJoin.new(
                  discord_gateway: DiscordApiGateway.new(configuration),
                  discord_role_map: DiscordRoleMap.new,
                  invite_repository: invite_repository,
                  connection_repository: connection_repository,
                  access_read_model: access_read_model
                ),
                logger: logger
              )
            end

            def initialize(guild_id:, bot:, join_handler:, logger: $stdout,
                           detector: PolishOpenSourceRank::Application::DiscordInviteUseDetector.new)
              @bot = bot
              @guild_id = guild_id.to_i
              @join_handler = join_handler
              @detector = detector
              @invite_uses = {}
              @logger = logger
            end

            def run
              bot.ready { refresh_invites }
              bot.invite_create { refresh_invites }
              bot.invite_delete { refresh_invites }
              bot.member_join { |event| sync_joined_member(event) }
              bot.run
            end

            private

            attr_reader :bot, :guild_id, :join_handler, :detector, :logger

            class << self
              private

              def repositories_from_store(store)
                [store, store, store]
              end

              def repositories_from_database(configuration)
                database = Shared::Infrastructure::SQLite::Database.open(configuration.database_path)
                PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration.new(
                  database,
                  PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql
                ).bootstrap!
                [
                  Contexts::Community::Infrastructure::SQLite::SQLiteDiscordInviteRepository.new(database),
                  Contexts::Community::Infrastructure::SQLite::SQLiteDiscordConnectionRepository.new(database),
                  Contexts::Community::Infrastructure::SQLite::SQLiteContributorAccessReadModel.new(database)
                ]
              end
            end

            def sync_joined_member(event)
              previous_uses = @invite_uses
              current_uses = fetch_invite_uses
              @invite_uses = current_uses
              invite_code = detector.used_code(previous_uses, current_uses)

              unless invite_code
                logger.puts("discord invite join skipped: invite code ambiguous for #{event.user.id}")
                return
              end

              synced = join_handler.call(
                invite_code: invite_code,
                discord_user_id: event.user.id.to_s,
                discord_username: event.user.global_name || event.user.username
              )
              logger.puts("discord invite #{invite_code} synced for #{event.user.id}: #{synced}")
            rescue StandardError => e
              logger.puts("discord invite join failed for #{event.user.id}: #{e.class}: #{e.message}")
            end

            def refresh_invites
              @invite_uses = fetch_invite_uses
              logger.puts("discord invite cache refreshed: #{@invite_uses.size} invites")
            rescue StandardError => e
              logger.puts("discord invite cache refresh failed: #{e.class}: #{e.message}")
            end

            def fetch_invite_uses
              server.invites.to_h { |invite| [invite.code, invite.uses.to_i] }
            end

            def server
              bot.server(guild_id) || raise("Discord guild #{guild_id} not found")
            end
          end
        end
      end
    end
  end
end
