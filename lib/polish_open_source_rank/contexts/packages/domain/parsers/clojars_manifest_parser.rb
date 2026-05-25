# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class ClojarsManifestParser
            def parse(path:, content:)
              name = package_name(path, content)
              PackageManifest.new(
                ecosystem: 'clojars',
                package_name: name,
                repository_url: repository_url(content),
                homepage_url: homepage_url(content),
                license: license(content),
                confidence: name ? confidence(path) : 'low',
                parse_status: name ? parse_status(path) : 'partial',
                metadata: { path: path, version: version(content) }
              )
            end

            private

            def package_name(path, content)
              return content[/\(defproject\s+([^\s]+)\s+["'][^"']+["']/, 1] if File.basename(path) == 'project.clj'
              return content[/\(def\s+project\s+['"]?([^\s)]+)['"]?\)/, 1] if File.basename(path) == 'build.boot'

              content[/:(?:project\/)?name\s+([^\s}]+)/, 1]&.delete('"')
            end

            def repository_url(content)
              content[/:url\s+["']([^"']+)["']/, 1] || content[/:scm\s+\{[^}]*:url\s+["']([^"']+)["']/m, 1]
            end

            def homepage_url(content)
              content[/:url\s+["']([^"']+)["']/, 1]
            end

            def license(content)
              content[/:license\s+\{[^}]*:name\s+["']([^"']+)["']/m, 1]
            end

            def version(content)
              content[/\(defproject\s+[^\s]+\s+["']([^"']+)["']/, 1]
            end

            def confidence(path)
              File.basename(path) == 'deps.edn' ? 'medium' : 'high'
            end

            def parse_status(path)
              File.basename(path) == 'deps.edn' ? 'partial' : 'parsed'
            end
          end
        end
      end
    end
  end
end
