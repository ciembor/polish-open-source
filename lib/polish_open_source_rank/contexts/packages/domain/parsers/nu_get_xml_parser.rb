# frozen_string_literal: true

require 'rexml/document'

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class NuGetXmlParser
            PROJECT_EXTENSIONS = %w[.csproj .fsproj .vbproj].freeze

            def parse(path:, content:)
              document = REXML::Document.new(content)
              if File.basename(path) == 'Directory.Packages.props'
                central_package_versions(path, document)
              elsif File.extname(path) == '.nuspec'
                nuspec(path, document)
              else
                project(path, document)
              end
            rescue REXML::ParseException => e
              StaticManifestParserHelpers.failed('nuget', e.message)
            end

            private

            def project(path, document)
              return unsupported(path) unless PROJECT_EXTENSIONS.include?(File.extname(path))

              name = text(document, 'PackageId') || text(document, 'AssemblyName')
              PackageManifest.new(
                ecosystem: 'nuget',
                package_name: name,
                repository_url: text(document, 'RepositoryUrl'),
                homepage_url: text(document, 'PackageProjectUrl') || text(document, 'ProjectUrl'),
                license: text(document, 'PackageLicenseExpression') || text(document, 'PackageLicenseFile'),
                confidence: name ? 'high' : 'medium',
                parse_status: name ? 'parsed' : 'partial',
                metadata: project_metadata(path, document)
              )
            end

            def nuspec(path, document)
              PackageManifest.new(
                ecosystem: 'nuget',
                package_name: text(document, 'id'),
                repository_url: repository_url(document),
                homepage_url: text(document, 'projectUrl'),
                license: text(document, 'license') || text(document, 'licenseUrl'),
                confidence: text(document, 'id') ? 'high' : 'low',
                parse_status: text(document, 'id') ? 'parsed' : 'partial',
                metadata: { path: path, version: text(document, 'version') }.compact
              )
            end

            def central_package_versions(path, document)
              package_versions = elements(document, 'PackageVersion').filter_map do |element|
                package_version(element)
              end
              PackageManifest.new(
                ecosystem: 'nuget',
                confidence: 'medium',
                parse_status: 'partial',
                metadata: { path: path, package_versions: package_versions }
              )
            end

            def project_metadata(path, document)
              {
                path: path,
                version: package_version_text(document),
                package_references: elements(document, 'PackageReference').filter_map do |element|
                  package_reference(element)
                end
              }.compact
            end

            def package_version_text(document)
              text(document, 'PackageVersion') || text(document, 'Version') || text(document, 'VersionPrefix')
            end

            def package_reference(element)
              id = attribute(element, 'Include') || attribute(element, 'Update')
              return unless id

              { id: id, version: attribute(element, 'Version') }.compact
            end

            def package_version(element)
              id = attribute(element, 'Include') || attribute(element, 'Update')
              return unless id

              { id: id, version: attribute(element, 'Version') }.compact
            end

            def repository_url(document)
              element = elements(document, 'repository').first
              element && attribute(element, 'url')
            end

            def text(document, name)
              element = elements(document, name).first
              value = element&.text&.strip
              value.nil? || value.empty? ? nil : value
            end

            def elements(document, name)
              matches = []
              collect_elements(document.root, name, matches) if document.root
              matches
            end

            def collect_elements(element, name, matches)
              matches << element if element.name == name
              element.elements.each { |child| collect_elements(child, name, matches) }
            end

            def attribute(element, name)
              value = element.attributes[name]&.strip
              value.nil? || value.empty? ? nil : value
            end

            def unsupported(path)
              StaticManifestParserHelpers.failed('nuget', "unsupported NuGet XML manifest: #{path}")
            end
          end
        end
      end
    end
  end
end
