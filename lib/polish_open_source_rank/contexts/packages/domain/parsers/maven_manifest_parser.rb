# frozen_string_literal: true

require 'rexml/document'

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class MavenManifestParser
            def parse(path:, content:)
              if File.basename(path) == 'pom.xml'
                parse_pom(path, content)
              else
                parse_gradle(path, content)
              end
            end

            private

            def parse_pom(path, content)
              document = REXML::Document.new(content)
              root = document.root
              group_id = child_text(root, 'groupId') || child_text(child(root, 'parent'), 'groupId')
              artifact_id = child_text(root, 'artifactId')
              package_name = coordinate(group_id, artifact_id)
              PackageManifest.new(
                ecosystem: 'maven',
                package_name: package_name,
                repository_url: child_text(child(root, 'scm'), 'url'),
                homepage_url: child_text(root, 'url'),
                license: child_text(child(child(root, 'licenses'), 'license'), 'name'),
                confidence: package_name ? 'high' : 'medium',
                parse_status: package_name ? 'parsed' : 'partial',
                metadata: pom_metadata(root, path, group_id, artifact_id)
              )
            rescue REXML::ParseException => e
              StaticManifestParserHelpers.failed('maven', e.message)
            end

            def parse_gradle(path, content)
              group_id = gradle_assignment(content, 'group')
              artifact_id = gradle_assignment(content, 'archivesName') || gradle_assignment(content, 'rootProject.name')
              package_name = coordinate(group_id, artifact_id)
              PackageManifest.new(
                ecosystem: 'maven',
                package_name: package_name,
                repository_url: github_url(content),
                homepage_url: gradle_assignment(content, 'url'),
                license: gradle_assignment(content, 'license') || gradle_assignment(content, 'name'),
                confidence: package_name ? 'medium' : 'low',
                parse_status: 'partial',
                metadata: {
                  path: path,
                  group_id: group_id,
                  artifact_id: artifact_id,
                  version: gradle_assignment(content, 'version'),
                  project_name: gradle_assignment(content, 'rootProject.name')
                }.compact
              )
            end

            def child(element, name)
              element&.elements&.find { |candidate| candidate.name == name }
            end

            def child_text(element, name)
              value = child(element, name)&.text&.strip
              value.nil? || value.empty? ? nil : value
            end

            def pom_metadata(root, path, group_id, artifact_id)
              {
                path: path,
                group_id: group_id,
                artifact_id: artifact_id,
                version: child_text(root, 'version') || child_text(child(root, 'parent'), 'version')
              }.compact
            end

            def coordinate(group_id, artifact_id)
              return if group_id.nil? || artifact_id.nil?

              "#{group_id}:#{artifact_id}"
            end

            def gradle_assignment(content, name)
              patterns = [
                /^\s*#{Regexp.escape(name)}\s*=\s*["']([^"']+)["']/,
                /^\s*#{Regexp.escape(name)}\s+["']([^"']+)["']/
              ]
              match = patterns.filter_map { |pattern| content.match(pattern) }.first
              match && match[1]
            end

            def github_url(content)
              content[%r{https://github\.com/[^\s"',)]+}, 0]
            end
          end
        end
      end
    end
  end
end
