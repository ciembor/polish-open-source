# frozen_string_literal: true

require 'discordrb'

module PolishOpenSourceRank
  module Contexts
    module Community
      module Infrastructure
        module Discord
          class DiscordInviteBot
            def self.build(configuration:, logger: $stdout)
              repositories = repositories_from_database(configuration)
              new(
                guild_id: configuration.discord_guild_id,
                bot: Discordrb::Bot.new(token: configuration.discord_bot_token, intents: %i[server_invites]),
                join_handler: Contexts::Community::Application::DiscordInviteJoin.new(
                  invite_repository: repositories.fetch(:invite_repository),
                  connection_repository: repositories.fetch(:connection_repository),
                  sync_job_repository: repositories.fetch(:sync_job_repository)
                ),
                sync_handler: sync_handler(configuration, repositories),
                logger: logger
              )
            end

            def initialize(guild_id:, bot:, join_handler:, sync_handler: nil, logger: $stdout,
                           detector: Contexts::Community::Application::DiscordInviteUseDetector.new)
              @bot = bot
              @guild_id = guild_id.to_i
              @join_handler = join_handler
              @sync_handler = sync_handler
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

            attr_reader :bot, :guild_id, :join_handler, :sync_handler, :detector, :logger

            class << self
              private

              def repositories_from_database(configuration)
                database = Shared::Infrastructure::SQLite::Database.open(configuration.database_path)
                PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration.new(
                  database,
                  PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql
                ).bootstrap!
                {
                  invite_repository: Contexts::Community::Infrastructure::SQLite::SQLiteDiscordInviteRepository.new(database),
                  connection_repository:
                    Contexts::Community::Infrastructure::SQLite::SQLiteDiscordConnectionRepository.new(database),
                  sync_job_repository:
                    Contexts::Community::Infrastructure::SQLite::SQLiteDiscordSyncJobRepository.new(database),
                  access_read_model:
                    Contexts::Community::Infrastructure::SQLite::SQLiteContributorAccessReadModel.new(database),
                  profile_read_model:
                    Contexts::Publication::Infrastructure::SQLite::SQLiteProfileReadModel.new(database)
                }
              end

              def sync_handler(configuration, repositories)
                gateway = DiscordApiGateway.new(configuration)
                Contexts::Community::Application::SyncDiscordConnection.new(
                  sync_job_repository: repositories.fetch(:sync_job_repository),
                  profile_read_model: repositories.fetch(:profile_read_model),
                  access_read_model: repositories.fetch(:access_read_model),
                  member_gateway: gateway,
                  role_map: DiscordRoleMap.new(
                    gateway: gateway,
                    published_language_source: repositories.fetch(:access_read_model)
                  )
                )
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
              sync_handler&.call(period_start: nil, limit: 10)
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
