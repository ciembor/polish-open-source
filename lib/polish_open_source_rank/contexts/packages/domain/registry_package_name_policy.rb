# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module RegistryPackageNamePolicy
          PLACEHOLDER_PACKAGE_NAMES = %w[bar baz dummy example foo src test].freeze

          module_function

          def ignored?(ecosystem:, normalized_package_name:)
            return true if invalid_npm_package_name?(ecosystem, normalized_package_name)
            return false unless %w[pypi rubygems].include?(ecosystem)

            PLACEHOLDER_PACKAGE_NAMES.include?(normalized_package_name)
          end

          def error_for(ecosystem:)
            return 'invalid npm package name' if ecosystem == 'npm'

            'placeholder package name'
          end

          def invalid_npm_package_name?(ecosystem, normalized_package_name)
            return false unless ecosystem == 'npm'
            return false unless normalized_package_name.include?('/')

            !normalized_package_name.match?(%r{\A@[^/\s]+/[^/\s]+\z})
          end
        end
      end
    end
  end
end
