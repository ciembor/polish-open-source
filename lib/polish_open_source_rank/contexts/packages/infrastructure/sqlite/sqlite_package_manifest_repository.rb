# frozen_string_literal: true

require 'digest'

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module SQLite
          class SQLitePackageManifestRepository
            include SQLiteRetryableErrors

            PARSER_VERSION = 'manifest-parser-v5'

            def initialize(database, clock: -> { Time.now.utc }, parser_catalog: Domain::ManifestParserCatalog.new,
                           work_events: Operations::Application::JobWorkEventRecorder.new)
              @database = database
              @clock = clock
              @parser_catalog = parser_catalog
              @work_events = work_events
            end

            def replace_detected(scan_id, manifests:, blobs:)
              translate_retryable_sqlite_failure do
                context = scan_context(scan_id)
                database.transaction do
                  delete_registry_package_links(scan_id)
                  package_manifests.where(repository_scan_id: scan_id).delete
                  manifests.each { |manifest| insert_manifest(scan_id, manifest, blobs.fetch(manifest.path), context) }
                end
              end
            end

            private

            attr_reader :clock, :database, :parser_catalog, :work_events

            def insert_manifest(scan_id, manifest, content, context)
              record_work_event(manifest, context) do
                parsed_manifest = parser_catalog.parse(
                  path: manifest.path,
                  ecosystem: manifest.ecosystem,
                  content: content
                )
                parsed_manifest = Domain::RepositoryBackedPackageIdentity.apply(parsed_manifest, context)
                package_manifests.insert(manifest_attributes(scan_id, manifest, parsed_manifest, content))
                parsed_manifest.parse_status
              end
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

            def delete_registry_package_links(scan_id)
              database.execute(
                <<~SQL,
                  DELETE FROM registry_package_links
                  WHERE manifest_id IN (
                    SELECT id FROM package_manifests
                    WHERE repository_scan_id = ?
                  )
                SQL
                [scan_id]
              )
            end

            def scan_context(scan_id)
              database.fetch_all(
                <<~SQL,
                  SELECT period_start, repository_kind, platform, repository_source_id, full_name
                  FROM package_repository_scans
                  WHERE id = ?
                  LIMIT 1
                SQL
                [scan_id]
              ).first
            end

            def record_work_event(manifest, context, &)
              work_events.record_timed(
                period_start: context.fetch(:period_start),
                job_kind: 'packages',
                stage: 'manifest_parse',
                unit_kind: 'package_manifest',
                platform: context.fetch(:platform),
                ecosystem: manifest.ecosystem,
                subject_id: "#{context.fetch(:repository_source_id)}:#{manifest.path}",
                subject_label: "#{context.fetch(:full_name)}:#{manifest.path}", &
              )
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
