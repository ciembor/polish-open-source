# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class NixPackageParser
            def parse(path:, content:)
              name = pname(content) || flake_name(content)
              PackageManifest.new(
                ecosystem: 'nix',
                package_name: name,
                repository_url: meta_value(content, 'homepage'),
                homepage_url: meta_value(content, 'homepage'),
                license: license(content),
                confidence: name ? 'medium' : 'low',
                parse_status: name ? 'parsed' : 'partial',
                metadata: { path: path, version: assignment(content, 'version') }
              )
            end

            private

            def pname(content)
              assignment(content, 'pname') || assignment(content, 'name')
            end

            def flake_name(content)
              content[/description\s*=\s*["']([^"']+)["']/, 1]
            end

            def assignment(content, key)
              content[/^\s*#{Regexp.escape(key)}\s*=\s*["']([^"']+)["']\s*;/, 1]
            end

            def meta_value(content, key)
              content[/^\s*#{Regexp.escape(key)}\s*=\s*["']([^"']+)["']\s*;/, 1]
            end

            def license(content)
              content[/^\s*license\s*=\s*(?:lib\.)?licenses\.([a-zA-Z0-9_+-]+)\s*;/, 1]
            end
          end
        end
      end
    end
  end
end
