# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Ecosystem
          SUPPORTED = %w[npm rubygems crates pypi hex packagist go nuget maven].freeze

          module_function

          def supported?(ecosystem)
            ecosystem.nil? || SUPPORTED.include?(ecosystem)
          end
        end
      end
    end
  end
end
