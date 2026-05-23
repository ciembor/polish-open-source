# frozen_string_literal: true

require 'digest'

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module SQLite
          class SQLitePackageManifestRepository
            PARSER_VERSION = 'detector-v1'

            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def replace_detected(scan_id, manifests:, blobs:)
              database.transaction do
                package_manifests.where(repository_scan_id: scan_id).delete
                manifests.each { |manifest| insert_manifest(scan_id, manifest, blobs.fetch(manifest.path)) }
              end
            end

            private

            attr_reader :clock, :database

            def insert_manifest(scan_id, manifest, content)
              package_manifests.insert(
                repository_scan_id: scan_id,
                ecosystem: manifest.ecosystem,
                path: manifest.path,
                blob_sha: Digest::SHA256.hexdigest(content.to_s),
                confidence: 'low',
                parse_status: 'partial',
                parser_version: PARSER_VERSION,
                parsed_at: timestamp
              )
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
