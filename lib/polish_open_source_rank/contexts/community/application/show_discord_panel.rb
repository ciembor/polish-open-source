# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Application
        # Builds the Discord account panel from ranking access and sync state.
        class ShowDiscordPanel
          # Lightweight view model for the Discord account settings screen.
          Panel = Struct.new(:connection, :sync_status, :access, :access_groups, keyword_init: true) do
            def fetch(key, *fallback, &)
              to_h.fetch(key, *fallback, &)
            end
          end

          def initialize(connection_repository:, sync_job_repository:, access_read_model:,
                         role_catalog: Contexts::Community::Domain::DiscordRoleCatalog.new)
            @connection_repository = connection_repository
            @sync_job_repository = sync_job_repository
            @access_read_model = access_read_model
            @role_catalog = role_catalog
          end

          def call(platform:, source_id:, period_start:)
            access = access_read_model.discord_access(platform, source_id, period_start: period_start)
            Panel.new(
              connection: connection_repository.discord_connection(platform, source_id),
              sync_status: sync_job_repository.sync_status(platform, source_id),
              access: access,
              access_groups: access_groups(access.fetch(:access_role_keys))
            )
          end

          private

          attr_reader :access_read_model, :connection_repository, :role_catalog, :sync_job_repository

          def access_groups(role_keys)
            role_keys.filter_map { |role_key| role_catalog.role_name(role_key) }
          end
        end
      end
    end
  end
end
