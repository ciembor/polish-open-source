# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Application
        class ScanRepositoryManifests
          DEFAULT_LIMIT = 100

          def initialize(repository_queue:, tree_gateway:, manifest_repository:,
                         detector: Domain::ManifestDetector,
                         work_events: Operations::Application::JobWorkEventRecorder.new)
            @repository_queue = repository_queue
            @tree_gateway = tree_gateway
            @manifest_repository = manifest_repository
            @detector = detector
            @work_events = work_events
          end

          def call(period, ecosystem: nil, limit: DEFAULT_LIMIT, refresh: false)
            stats = { scanned: 0, failed: 0, manifests: 0 }
            repository_queue.pending(period, limit: limit, ecosystem: ecosystem, refresh: refresh).each do |scan|
              result = scan_repository(scan, ecosystem: ecosystem, refresh: refresh)
              status = result.fetch(:status)
              stats[:scanned] += 1 if status == :scanned
              stats[:failed] += 1 if failure_status?(status)
              stats[:manifests] += result.fetch(:manifest_count)
            end
            stats
          end

          private

          attr_reader :detector, :manifest_repository, :repository_queue, :tree_gateway, :work_events

          def failure_status?(status)
            %i[failed unavailable].include?(status)
          end

          def scan_repository(scan, ecosystem:, refresh:)
            record_work_event(scan, ecosystem: ecosystem) do
              repository_queue.mark_processing(scan.fetch(:id))
              tree = tree_for(scan)
              if unchanged?(scan, tree, refresh)
                mark_unchanged(scan, tree)
              else
                scan_changed_repository(scan, tree, ecosystem)
              end
            end
          rescue RepositoryUnavailable => e
            repository_queue.mark_unavailable(scan.fetch(:id), e.message)
            { status: :unavailable, manifest_count: 0 }
          end

          def record_work_event(scan, ecosystem:, &)
            work_events.record_timed(
              period_start: scan.fetch(:period_start),
              job_kind: 'packages',
              stage: 'repository_scan',
              unit_kind: 'package_repository_scan',
              platform: scan.fetch(:platform),
              ecosystem: ecosystem,
              subject_id: scan.fetch(:repository_source_id),
              subject_label: scan.fetch(:full_name), &
            )
          end

          def tree_for(scan)
            metadata = tree_gateway.repository(scan.fetch(:full_name))
            tree_gateway.tree(scan.fetch(:full_name), ref: metadata.fetch(:default_branch))
          end

          def scan_changed_repository(scan, tree, ecosystem)
            manifests = detected_manifests(tree, ecosystem)
            blobs = manifest_blobs(scan.fetch(:full_name), tree.entries, manifests)
            manifest_repository.replace_detected(scan.fetch(:id), manifests: manifests, blobs: blobs)
            repository_queue.mark_scanned(
              scan.fetch(:id),
              tree_sha: tree.sha,
              tree_truncated: tree.truncated,
              manifest_count: manifests.length
            )
            { status: :scanned, manifest_count: manifests.length }
          end

          def detected_manifests(tree, ecosystem)
            manifests = detector.detect_paths(tree.entries.map { |entry| entry.fetch(:path) })
            ecosystem ? manifests.select { |manifest| manifest.ecosystem == ecosystem } : manifests
          end

          def unchanged?(scan, tree, refresh)
            !refresh && scan[:tree_sha] == tree.sha
          end

          def mark_unchanged(scan, tree)
            repository_queue.mark_scanned(
              scan.fetch(:id),
              tree_sha: tree.sha,
              tree_truncated: tree.truncated,
              manifest_count: scan.fetch(:manifest_count)
            )
            { status: :scanned, manifest_count: 0 }
          end

          def manifest_blobs(full_name, entries, manifests)
            entries_by_path = entries.to_h { |entry| [entry.fetch(:path), entry] }
            manifests.to_h do |manifest|
              entry = entries_by_path.fetch(manifest.path)
              [manifest.path, tree_gateway.blob(full_name, sha: entry.fetch(:sha))]
            end
          end
        end
      end
    end
  end
end
