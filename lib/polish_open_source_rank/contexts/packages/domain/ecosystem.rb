# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Ecosystem
          SUPPORTED = %w[npm rubygems crates pypi hex packagist go homebrew nuget maven].freeze
          SNAPSHOT_SUPPORTED = %w[npm rubygems crates pypi hex packagist go homebrew nuget maven].freeze

          module_function

          def supported?(ecosystem)
            ecosystem.nil? || SUPPORTED.include?(ecosystem)
          end

          def snapshot_supported?(ecosystem)
            ecosystem.nil? || SNAPSHOT_SUPPORTED.include?(ecosystem)
          end

          def snapshot_supported
            SNAPSHOT_SUPPORTED
          end

          def snapshot_supported_list
            SNAPSHOT_SUPPORTED.join(', ')
          end
        end
      end
    end
  end
end
