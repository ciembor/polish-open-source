# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Domain
        # Holds the prepared Discord role ids resolved for one ranking snapshot.
        class DiscordRoleResolution
          attr_reader :managed_role_ids, :role_ids

          def initialize(role_ids:, managed_role_ids:)
            @role_ids = role_ids
            @managed_role_ids = managed_role_ids
          end
        end
      end
    end
  end
end
