# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class GoModParser
            def parse(path:, content:)
              name = module_name(content)
              PackageManifest.new(
                ecosystem: 'go',
                package_name: name,
                confidence: name ? 'high' : 'medium',
                parse_status: name ? 'parsed' : 'partial',
                metadata: { path: path }
              )
            end

            private

            def module_name(content)
              unquote_module_path(content[/^\s*module\s+(\S+)/, 1])
            end

            def unquote_module_path(name)
              return unless name
              return name unless quoted?(name)

              name[1...-1]
            end

            def quoted?(name)
              (name.start_with?('"') && name.end_with?('"')) ||
                (name.start_with?('`') && name.end_with?('`'))
            end
          end
        end
      end
    end
  end
end
