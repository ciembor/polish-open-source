# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class PubspecYamlParser
            def parse(path:, content:)
              name = yaml_scalar(content, 'name')
              publish_to = yaml_scalar(content, 'publish_to')
              PackageManifest.new(
                ecosystem: 'pub',
                package_name: name,
                custom_registry: custom_registry(publish_to),
                repository_url: yaml_scalar(content, 'repository'),
                homepage_url: yaml_scalar(content, 'homepage'),
                confidence: name ? 'high' : 'low',
                parse_status: parse_status(name, publish_to),
                metadata: { path: path, version: yaml_scalar(content, 'version') }
              )
            end

            private

            def yaml_scalar(content, key)
              value = content[/^\s*#{Regexp.escape(key)}:\s*["']?([^"'\n#]+)["']?/, 1]
              value&.strip
            end

            def custom_registry(publish_to)
              publish_to unless publish_to.nil? || publish_to == 'none' || publish_to == 'https://pub.dev'
            end

            def parse_status(name, publish_to)
              return 'failed' unless name
              return 'private' if publish_to == 'none'
              return 'custom_registry' if custom_registry(publish_to)

              'parsed'
            end
          end
        end
      end
    end
  end
end
