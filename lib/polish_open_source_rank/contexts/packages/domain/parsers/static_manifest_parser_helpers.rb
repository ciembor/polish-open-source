# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          module StaticManifestParserHelpers
            module_function

            def failed(ecosystem, error)
              PackageManifest.new(ecosystem: ecosystem, confidence: 'low', parse_status: 'failed',
                                  metadata: { error: error })
            end

            def section(content, name)
              content[/^\s*\[#{Regexp.escape(name)}\]\s*$\n?(.*?)(?=^\s*\[|\z)/m, 1].to_s
            end

            def assignment(content, key)
              match = content.match(/^\s*#{Regexp.escape(key)}\s*=\s*["']([^"']+)["']/)
              match && match[1]
            end

            def boolean_assignment(content, key)
              match = content.match(/^\s*#{Regexp.escape(key)}\s*=\s*(true|false)\b/)
              match && match[1] == 'true'
            end

            def array_assignment(content, key)
              match = content.match(/^\s*#{Regexp.escape(key)}\s*=\s*\[(.*?)\]/m)
              return [] unless match

              match[1].scan(/["']([^"']+)["']/).flatten
            end

            def ruby_assignment(content, attribute)
              match = content.match(/^\s*\w+\.#{Regexp.escape(attribute)}\s*=\s*["']([^"']+)["']/)
              match && match[1]
            end

            def ruby_metadata(content, key)
              match = content.match(/^\s*\w+\.metadata\[['"]#{Regexp.escape(key)}['"]\]\s*=\s*["']([^"']+)["']/)
              match && match[1]
            end

            def python_setup_name(content)
              match = content.match(/setup\s*\(.*?\bname\s*=\s*["']([^"']+)["']/m)
              match && match[1]
            end

            def elixir_app_name(content)
              match = content.match(/\bapp:\s*:([a-zA-Z_]\w*)/)
              match && match[1]
            end

            def rebar_app_name(content)
              match = content.match(/\{app,\s*([a-zA-Z_]\w*)\}/)
              match && match[1]
            end
          end
        end
      end
    end
  end
end
