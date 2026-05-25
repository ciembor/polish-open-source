# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class CondaManifestParser
            def parse(path:, content:)
              name = package_name(content)
              PackageManifest.new(
                ecosystem: 'conda',
                package_name: name,
                repository_url: about_scalar(content, 'dev_url'),
                homepage_url: about_scalar(content, 'home'),
                license: about_scalar(content, 'license'),
                confidence: name ? 'medium' : 'low',
                parse_status: name ? 'parsed' : 'partial',
                metadata: { path: path, version: package_version(content) }
              )
            end

            private

            def package_name(content)
              section_scalar(content, 'package', 'name') || scalar(content, 'name')
            end

            def package_version(content)
              section_scalar(content, 'package', 'version')
            end

            def about_scalar(content, key)
              section_scalar(content, 'about', key)
            end

            def section_scalar(content, section, key)
              section_body = content[/^\s*#{Regexp.escape(section)}:\s*$\n(.*?)(?=^\S|\z)/m, 1].to_s
              scalar(section_body, key)
            end

            def scalar(content, key)
              content[/^\s*#{Regexp.escape(key)}:\s*["']?([^"'\n#]+)["']?/, 1]&.strip
            end
          end
        end
      end
    end
  end
end
