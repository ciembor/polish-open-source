# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    class Composition
      # Wires community identity and Discord use cases while keeping OAuth clients replaceable in tests.
      class Community
        def initialize(configuration:, persistence:, profile_read_model:, overrides: {})
          @dependencies = {
            configuration: configuration,
            persistence: persistence,
            profile_read_model: profile_read_model,
            overrides: overrides
          }
          @services = {}
        end

        def github_oauth_client
          service(:github_oauth_client) { Auth::GitHubOAuthClient.new(configuration) }
        end

        def discord_oauth_client
          service(:discord_oauth_client) { Auth::DiscordOAuthClient.new(configuration) }
        end

        def discord_gateway
          service(:discord_gateway) do
            Contexts::Community::Infrastructure::Discord::DiscordApiGateway.new(configuration)
          end
        end

        def discord_role_map
          service(:discord_role_map) do
            Contexts::Community::Infrastructure::Discord::DiscordRoleMap.new(
              gateway: discord_gateway,
              published_language_source: contributor_access_read_model
            )
          end
        end

        def show_discord_panel
          service(:show_discord_panel) do
            Contexts::Community::Application::ShowDiscordPanel.new(
              connection_repository: discord_connection_repository,
              sync_job_repository: discord_sync_job_repository,
              access_read_model: contributor_access_read_model
            )
          end
        end

        def connect_discord_account
          service(:connect_discord_account) do
            Contexts::Community::Application::ConnectDiscordAccount.new(
              profile_read_model: profile_read_model,
              connection_repository: discord_connection_repository,
              sync_job_repository: discord_sync_job_repository,
              access_read_model: contributor_access_read_model
            )
          end
        end

        def sync_discord_connection
          service(:sync_discord_connection) do
            Contexts::Community::Application::SyncDiscordConnection.new(
              sync_job_repository: discord_sync_job_repository,
              profile_read_model: profile_read_model,
              access_read_model: contributor_access_read_model,
              member_gateway: discord_gateway,
              role_map: discord_role_map
            )
          end
        end

        def contributor_access_read_model
          service(:contributor_access_read_model) do
            Contexts::Community::Infrastructure::SQLite::SQLiteContributorAccessReadModel.new(
              persistence.public_database
            )
          end
        end

        def discord_connection_repository
          service(:discord_connection_repository) do
            Contexts::Community::Infrastructure::SQLite::SQLiteDiscordConnectionRepository.new(persistence.database)
          end
        end

        private

        attr_reader :dependencies, :services

        def discord_sync_job_repository
          service(:discord_sync_job_repository) do
            Contexts::Community::Infrastructure::SQLite::SQLiteDiscordSyncJobRepository.new(persistence.database)
          end
        end

        def configuration
          dependencies.fetch(:configuration)
        end

        def persistence
          dependencies.fetch(:persistence)
        end

        def profile_read_model
          dependencies.fetch(:profile_read_model)
        end

        def service(name)
          services[name] ||= dependencies.fetch(:overrides)[name] || yield
        end
      end
    end
  end
end
