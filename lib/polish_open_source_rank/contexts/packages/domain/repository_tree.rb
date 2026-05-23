# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        class RepositoryTree
          attr_reader :entries, :sha, :truncated

          def initialize(sha:, entries:, truncated:)
            @sha = sha
            @entries = entries
            @truncated = truncated
          end
        end
      end
    end
  end
end
