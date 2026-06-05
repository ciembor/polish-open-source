# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          class ReplicatedPublicProfileRepository
            def initialize(repositories)
              @repositories = repositories
            end

            def upsert_github_profile(attributes)
              repositories.each { it.upsert_github_profile(attributes) }
            end

            def redact_profile(platform:, source_id:)
              repositories.each { it.redact_profile(platform: platform, source_id: source_id) }
            end

            private

            attr_reader :repositories
          end
        end
      end
    end
  end
end
