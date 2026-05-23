# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module ManifestDetector
          module_function

          def detect_paths(tree_paths)
            tree_paths
              .reject { |path| ManifestPatternCatalog.ignored?(path) }
              .filter_map { |path| manifest_path(path) }
              .sort_by { |manifest| [manifest.ecosystem, manifest.path] }
          end

          def manifest_path(path)
            ecosystem = ManifestPatternCatalog.ecosystem_for(path)
            ecosystem && ManifestPath.new(ecosystem: ecosystem, path: path)
          end
        end
      end
    end
  end
end
