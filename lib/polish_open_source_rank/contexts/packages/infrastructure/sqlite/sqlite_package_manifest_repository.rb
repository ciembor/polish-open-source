# frozen_string_literal: true

require 'digest'

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module SQLite
          class SQLitePackageManifestRepository
            PARSER_VERSION = 'manifest-parser-v1'

            def initialize(database, clock: -> { Time.now.utc }, parser_catalog: Domain::ManifestParserCatalog.new)
              @database = database
              @clock = clock
              @parser_catalog = parser_catalog
            end

            def replace_detected(scan_id, manifests:, blobs:)
              database.transaction do
                package_manifests.where(repository_scan_id: scan_id).delete
                manifests.each { |manifest| insert_manifest(scan_id, manifest, blobs.fetch(manifest.path)) }
              end
            end

            private

            attr_reader :clock, :database, :parser_catalog

            def insert_manifest(scan_id, manifest, content)
              parsed_manifest = parser_catalog.parse(
                path: manifest.path,
                ecosystem: manifest.ecosystem,
                content: content
              )
              package_manifests.insert(manifest_attributes(scan_id, manifest, parsed_manifest, content))
            end

            def manifest_attributes(scan_id, manifest, parsed_manifest, content)
              {
                repository_scan_id: scan_id,
                ecosystem: parsed_manifest.ecosystem,
                path: parsed_manifest.metadata.fetch(:path, manifest.path),
                blob_sha: Digest::SHA256.hexdigest(content.to_s),
                package_name: parsed_manifest.package_name,
                normalized_package_name: parsed_manifest.normalized_package_name,
                private_package: parsed_manifest.private_package ? 1 : 0,
                custom_registry: parsed_manifest.custom_registry,
                repository_url: parsed_manifest.repository_url,
                homepage_url: parsed_manifest.homepage_url,
                license: parsed_manifest.license,
                confidence: parsed_manifest.confidence,
                parse_status: parsed_manifest.parse_status,
                parser_version: PARSER_VERSION,
                metadata_json: JSON.generate(parsed_manifest.metadata),
                parsed_at: timestamp
              }
            end

            def package_manifests
              database.dataset(:package_manifests)
            end

            def timestamp
              clock.call.iso8601
            end
          end
        end
      end
    end
  end
end
