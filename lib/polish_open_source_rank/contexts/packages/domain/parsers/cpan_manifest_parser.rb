# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class CpanManifestParser
            def parse(path:, content:)
              attributes = attributes_for(path, content)
              PackageManifest.new(
                ecosystem: 'cpan',
                package_name: attributes[:name],
                repository_url: attributes[:repository_url],
                homepage_url: attributes[:homepage_url],
                license: attributes[:license],
                confidence: attributes[:name] ? attributes[:confidence] : 'low',
                parse_status: attributes[:name] ? attributes[:parse_status] : 'partial',
                metadata: { path: path, version: attributes[:version] }.compact
              )
            rescue JSON::ParserError => e
              StaticManifestParserHelpers.failed('cpan', e.message)
            end

            private

            def attributes_for(path, content)
              case File.basename(path)
              when 'META.json' then json_attributes(content)
              when 'META.yml', 'META.yaml' then yaml_attributes(content)
              else perl_attributes(content)
              end
            end

            def json_attributes(content)
              data = JSON.parse(content)
              {
                name: data['name'],
                repository_url: data.dig('resources', 'repository', 'url') || data.dig('resources', 'repository'),
                homepage_url: data.dig('resources', 'homepage'),
                license: Array(data['license']).join(', '),
                version: data['version'],
                confidence: 'high',
                parse_status: 'parsed'
              }
            end

            def yaml_attributes(content)
              {
                name: yaml_scalar(content, 'name'),
                repository_url: yaml_scalar(content, 'repository'),
                homepage_url: yaml_scalar(content, 'homepage'),
                license: yaml_scalar(content, 'license'),
                version: yaml_scalar(content, 'version'),
                confidence: 'medium',
                parse_status: 'partial'
              }
            end

            def perl_attributes(content)
              name = content[/\b(?:NAME|module_name)\s*=>\s*['"]([^'"]+)['"]/, 1] ||
                     content[/^\s*name\s+['"]([^'"]+)['"]/, 1]
              {
                name: name&.gsub(/:+/, '-'),
                repository_url: content[/\b(?:repository|repository_url)\s*=>\s*['"]([^'"]+)['"]/, 1],
                homepage_url: content[/\b(?:homepage|homepage_url)\s*=>\s*['"]([^'"]+)['"]/, 1],
                license: content[/\blicen[cs]e\s*=>\s*['"]([^'"]+)['"]/, 1],
                version: nil,
                confidence: 'medium',
                parse_status: 'partial'
              }
            end

            def yaml_scalar(content, key)
              content[/^\s*#{Regexp.escape(key)}:\s*['"]?([^'"\n#]+)['"]?/, 1]&.strip
            end
          end
        end
      end
    end
  end
end
