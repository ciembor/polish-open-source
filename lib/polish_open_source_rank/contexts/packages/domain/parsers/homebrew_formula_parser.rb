# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class HomebrewFormulaParser
            Helpers = StaticManifestParserHelpers

            def parse(path:, content:)
              name = formula_name(path)
              source_url = Helpers.ruby_string_call(content, 'url')
              PackageManifest.new(
                ecosystem: 'homebrew',
                package_name: name,
                repository_url: github_url(content),
                homepage_url: Helpers.ruby_string_call(content, 'homepage'),
                license: license(content),
                confidence: name ? 'high' : 'medium',
                parse_status: name ? 'parsed' : 'partial',
                metadata: { path: path, source_url: source_url }.compact
              )
            end

            private

            def formula_name(path)
              File.basename(path, '.rb').then { |name| name.empty? ? nil : name }
            end

            def github_url(content)
              content[%r{https://github\.com/[^\s"',)]+}, 0]
            end

            def license(content)
              Helpers.ruby_string_call(content, 'license') || license_expression(content)
            end

            def license_expression(content)
              line = content.lines.find { |candidate| candidate.match?(/^\s*license\s+/) }
              return unless line

              values = line.scan(/["']([^"']+)["']/).flatten
              values.empty? ? nil : values.join(', ')
            end
          end
        end
      end
    end
  end
end
