# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module SQLite
          module RegistryPackageNameFiltering
            private

            def ignored_package_row?(package_row)
              ignored_package_name?(package_row.fetch(:ecosystem),
                                    package_row.fetch(:normalized_package_name))
            end

            def placeholder_manifest?(manifest)
              ignored_package_name?(manifest.fetch(:ecosystem),
                                    manifest.fetch(:normalized_package_name))
            end

            def placeholder_package?(package)
              ignored_package_name?(package.ecosystem, package.normalized_package_name)
            end

            def ignored_package_error(ecosystem)
              Domain::RegistryPackageNamePolicy.error_for(ecosystem: ecosystem)
            end

            def ignored_package_name?(ecosystem, normalized_package_name)
              Domain::RegistryPackageNamePolicy.ignored?(
                ecosystem: ecosystem,
                normalized_package_name: normalized_package_name
              )
            end
          end
        end
      end
    end
  end
end
