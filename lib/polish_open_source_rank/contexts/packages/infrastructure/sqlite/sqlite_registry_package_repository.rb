# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module SQLite
          class SQLiteRegistryPackageRepository
            FETCHABLE_PARSE_STATUSES = %w[parsed partial].freeze
            PLACEHOLDER_PACKAGE_NAMES = %w[bar baz dummy example foo src test].freeze
            REGISTRY_URLS = {
              'npm' => 'https://www.npmjs.com/package/%s',
              'rubygems' => 'https://rubygems.org/gems/%s',
              'crates' => 'https://crates.io/crates/%s',
              'pypi' => 'https://pypi.org/project/%s/',
              'hex' => 'https://hex.pm/packages/%s',
              'packagist' => 'https://packagist.org/packages/%s',
              'go' => 'https://pkg.go.dev/%s',
              'homebrew' => 'https://formulae.brew.sh/formula/%s',
              'nuget' => 'https://www.nuget.org/packages/%s',
              'maven' => 'https://central.sonatype.com/artifact/%s',
              'terraform' => 'https://registry.terraform.io/search/modules?q=%s',
              'conan' => 'https://conan.io/center/recipes/%s',
              'vcpkg' => 'https://vcpkg.io/en/package/%s.html',
              'swiftpm' => 'https://swiftpackageindex.com/search?query=%s',
              'pub' => 'https://pub.dev/packages/%s',
              'apt' => 'https://packages.debian.org/search?keywords=%s',
              'rpm' => 'https://src.fedoraproject.org/rpms/%s',
              'nix' => 'https://search.nixos.org/packages?query=%s',
              'cran' => 'https://cran.r-project.org/package=%s',
              'cpan' => 'https://metacpan.org/dist/%s',
              'hackage' => 'https://hackage.haskell.org/package/%s',
              'clojars' => 'https://clojars.org/%s',
              'julia' => 'https://juliahub.com/ui/Packages/General/%s',
              'conda' => 'https://anaconda.org/search?q=%s'
            }.freeze

            def initialize(database, clock: -> { Time.now.utc },
                           work_events: Operations::Application::JobWorkEventRecorder.new)
              @database = database
              @clock = clock
              @work_events = work_events
            end

            def resolve_from_manifests(period, ecosystem: nil, limit: 100)
              database.transaction do
                fetchable_manifests(period, ecosystem: ecosystem, limit: limit).each do |manifest|
                  next if placeholder_manifest?(manifest)

                  record_resolve_event(period, manifest) do
                    upsert_pending_package(manifest)
                    link_manifest(manifest)
                    'resolved'
                  end
                end
              end
            end

            def packages_to_fetch(period, ecosystem: nil, limit: 100, refresh: false)
              dataset = registry_packages.where(Sequel[:registry_packages][:ecosystem] => ecosystems_for(ecosystem))
              dataset = dataset.exclude(Sequel[:registry_packages][:status] => 'not_found') unless refresh
              dataset = without_snapshot(dataset, period) unless refresh
              dataset = dataset
                        .order(
                          Sequel.asc(Sequel[:registry_packages][:ecosystem]),
                          Sequel.asc(Sequel[:registry_packages][:normalized_package_name])
                        )
              apply_limit(dataset, limit).all
            end

            def record_fetch_result(period, package_row, result)
              database.transaction do
                if result.ok?
                  record_success(period, result)
                elsif result.package
                  record_package_context(result.package)
                else
                  record_failure(package_row, result)
                end
              end
            end

            private

            attr_reader :clock, :database, :work_events

            def fetchable_manifests(period, ecosystem:, limit:)
              dataset = package_manifests
                        .join(:package_repository_scans, id: :repository_scan_id)
                        .where(
                          Sequel[:package_repository_scans][:period_start] => period_start(period),
                          Sequel[:package_manifests][:parse_status] => FETCHABLE_PARSE_STATUSES
                        )
                        .exclude(Sequel[:package_manifests][:normalized_package_name] => nil)
              dataset = dataset.where(Sequel[:package_manifests][:ecosystem] => ecosystem) if ecosystem
              dataset = dataset
                        .select_all(:package_manifests)
                        .order(Sequel.asc(Sequel[:package_manifests][:id]))
              apply_limit(dataset, limit).all
            end

            def upsert_pending_package(manifest)
              registry_packages.insert_conflict(
                target: %i[ecosystem normalized_package_name],
                update: {
                  package_name: Sequel[:excluded][:package_name],
                  repository_url: Sequel[:excluded][:repository_url],
                  homepage_url: Sequel[:excluded][:homepage_url],
                  license: Sequel[:excluded][:license],
                  updated_at: timestamp
                }
              ).insert(
                ecosystem: manifest.fetch(:ecosystem),
                package_name: manifest.fetch(:package_name),
                normalized_package_name: manifest.fetch(:normalized_package_name),
                registry_url: registry_url(manifest.fetch(:ecosystem), manifest.fetch(:package_name)),
                repository_url: manifest[:repository_url],
                homepage_url: manifest[:homepage_url],
                license: manifest[:license],
                status: 'pending',
                updated_at: timestamp
              )
            end

            def link_manifest(manifest)
              registry_package_links.insert_conflict(
                target: %i[manifest_id ecosystem normalized_package_name],
                update: { match_confidence: Sequel[:excluded][:match_confidence], checked_at: timestamp }
              ).insert(
                manifest_id: manifest.fetch(:id),
                ecosystem: manifest.fetch(:ecosystem),
                normalized_package_name: manifest.fetch(:normalized_package_name),
                match_confidence: manifest.fetch(:confidence),
                matched: 1,
                checked_at: timestamp
              )
            end

            def record_success(period, result)
              package = result.package
              if placeholder_package?(package)
                record_rejected_package(package, error: 'placeholder package name')
                return
              end

              verification = verify_repository_links(package)
              if verification.fetch(:accepted_links).zero? && verification.fetch(:rejected_links).positive?
                record_rejected_package(package, error: 'registry repository mismatch')
                return
              end

              snapshot = snapshot_with_repository_match(result.snapshot, verification)
              record_package_context(package)
              registry_package_snapshots.insert_conflict(
                target: %i[ecosystem normalized_package_name period_start],
                update: snapshot_update(snapshot)
              ).insert(snapshot_insert(period, snapshot))
            end

            def record_package_context(package)
              registry_packages.insert_conflict(
                target: %i[ecosystem normalized_package_name],
                update: registry_package_update(package)
              ).insert(registry_package_insert(package))
            end

            def record_failure(package_row, result)
              registry_packages
                .where(
                  ecosystem: package_row.fetch(:ecosystem),
                  normalized_package_name: package_row.fetch(:normalized_package_name)
                )
                .update(
                  status: result.status,
                  error: result.error,
                  checked_at: timestamp,
                  updated_at: timestamp
                )
            end

            def record_rejected_package(package, error:)
              registry_packages
                .where(ecosystem: package.ecosystem, normalized_package_name: package.normalized_package_name)
                .update(
                  repository_url: package.repository_url,
                  homepage_url: package.homepage_url,
                  latest_version: package.latest_version,
                  status: 'not_found',
                  error: error,
                  checked_at: timestamp,
                  updated_at: timestamp
                )
            end

            def registry_package_insert(package)
              package.to_h.slice(
                :ecosystem, :package_name, :normalized_package_name, :registry_url, :repository_url,
                :homepage_url, :license, :latest_version, :status, :error
              ).merge(checked_at: timestamp, updated_at: timestamp)
            end

            def registry_package_update(package)
              attributes = registry_package_insert(package).slice(
                :package_name, :registry_url, :repository_url, :homepage_url, :license, :latest_version,
                :status, :error, :checked_at, :updated_at
              )
              preserve_existing_context_when_registry_is_silent(attributes)
            end

            def preserve_existing_context_when_registry_is_silent(attributes)
              attributes.reject do |key, value|
                value.nil? && %i[repository_url homepage_url license latest_version].include?(key)
              end
            end

            def snapshot_insert(period, snapshot)
              snapshot.to_h.slice(
                :ecosystem, :normalized_package_name, :downloads_total, :downloads_30d, :downloads_7d,
                :dependents_count, :dependent_repositories_count, :latest_version, :latest_release_at
              ).merge(period_start: period_start(period), metadata_json: JSON.generate(snapshot.metadata),
                      observed_at: timestamp)
            end

            def snapshot_update(snapshot)
              snapshot.to_h.slice(
                :downloads_total, :downloads_30d, :downloads_7d, :dependents_count,
                :dependent_repositories_count, :latest_version, :latest_release_at
              ).merge(metadata_json: JSON.generate(snapshot.metadata), observed_at: timestamp)
            end

            def without_snapshot(dataset, period)
              dataset
                .left_join(
                  :registry_package_snapshots,
                  ecosystem: Sequel[:registry_packages][:ecosystem],
                  normalized_package_name: Sequel[:registry_packages][:normalized_package_name],
                  period_start: period_start(period)
                )
                .where(Sequel[:registry_package_snapshots][:ecosystem] => nil)
                .select_all(:registry_packages)
            end

            def verify_repository_links(package)
              linked_manifests(package).each_with_object(initial_verification) do |manifest, verification|
                match = Contexts::Packages::Domain::RegistryPackageRepositoryMatch.call(
                  package: package,
                  manifest: manifest,
                  repository_full_name: manifest.fetch(:repository_full_name)
                )
                update_link_verification(manifest.fetch(:link_id), match)
                verification[:accepted_links] += 1 unless match.rejected?
                verification[:rejected_links] += 1 if match.rejected?
                verification[:matched_links] += 1 if match.matched?
              end
            end

            def initial_verification
              { accepted_links: 0, rejected_links: 0, matched_links: 0 }
            end

            def linked_manifests(package)
              registry_package_links
                .join(:package_manifests, id: Sequel[:registry_package_links][:manifest_id])
                .join(:package_repository_scans, id: Sequel[:package_manifests][:repository_scan_id])
                .where(
                  Sequel[:registry_package_links][:ecosystem] => package.ecosystem,
                  Sequel[:registry_package_links][:normalized_package_name] => package.normalized_package_name
                )
                .select(
                  Sequel[:registry_package_links][:id].as(:link_id),
                  Sequel[:package_repository_scans][:full_name].as(:repository_full_name),
                  Sequel[:package_manifests][:repository_url],
                  Sequel[:package_manifests][:homepage_url]
                )
                .all
            end

            def update_link_verification(link_id, match)
              registry_package_links
                .where(id: link_id)
                .update(
                  match_confidence: match.matched? ? 'high' : 'low',
                  matched: match.rejected? ? 0 : 1,
                  checked_at: timestamp
                )
            end

            def snapshot_with_repository_match(snapshot, verification)
              attributes = snapshot.to_h
              attributes[:metadata] = snapshot.metadata.merge(
                repository_match: repository_match_status(verification),
                repository_match_counts: verification
              )

              Contexts::Packages::Domain::RegistryPackageSnapshot.new(
                **attributes
              )
            end

            def repository_match_status(verification)
              return 'matched' if verification.fetch(:matched_links).positive?
              return 'unverified' if verification.fetch(:accepted_links).positive?

              'missing'
            end

            def placeholder_manifest?(manifest)
              placeholder_name?(manifest.fetch(:ecosystem), manifest.fetch(:normalized_package_name))
            end

            def placeholder_package?(package)
              placeholder_name?(package.ecosystem, package.normalized_package_name)
            end

            def placeholder_name?(ecosystem, normalized_package_name)
              return false unless %w[pypi rubygems].include?(ecosystem)

              PLACEHOLDER_PACKAGE_NAMES.include?(normalized_package_name)
            end

            def registry_url(ecosystem, package_name)
              return format(REGISTRY_URLS.fetch(ecosystem), package_name.tr(':', '/')) if ecosystem == 'maven'

              if repository_signal_ecosystem?(ecosystem)
                escaped = ::PolishOpenSourceRank::Contexts::Packages::Infrastructure::Registries::RegistryClientHelpers
                          .escaped_segment(package_name)
                return REGISTRY_URLS.fetch(ecosystem).sub('%s', escaped)
              end

              format(REGISTRY_URLS.fetch(ecosystem), package_name)
            end

            def repository_signal_ecosystem?(ecosystem)
              %w[
                terraform conan vcpkg swiftpm pub apt rpm nix cran cpan hackage clojars julia conda
              ].include?(ecosystem)
            end

            def ecosystems_for(ecosystem)
              ecosystem || Contexts::Packages::Domain::Ecosystem.snapshot_supported
            end

            def package_manifests
              database.dataset(:package_manifests)
            end

            def registry_packages
              database.dataset(:registry_packages)
            end

            def registry_package_links
              database.dataset(:registry_package_links)
            end

            def registry_package_snapshots
              database.dataset(:registry_package_snapshots)
            end

            def period_start(period)
              period.respond_to?(:start_date) ? period.start_date.to_s : period.to_s
            end

            def bounded_limit(limit)
              limit.to_i.clamp(1, 10_000)
            end

            def normalized_limit(limit)
              return nil if limit.to_s == 'all'

              bounded_limit(limit)
            end

            def apply_limit(dataset, limit)
              normalized = normalized_limit(limit)
              normalized ? dataset.limit(normalized) : dataset
            end

            def timestamp
              clock.call.iso8601
            end

            def record_resolve_event(period, manifest, &)
              work_events.record_timed(
                period_start: period_start(period),
                job_kind: 'packages',
                stage: 'registry_resolve',
                unit_kind: 'registry_package',
                platform: nil,
                ecosystem: manifest.fetch(:ecosystem),
                subject_id: manifest.fetch(:normalized_package_name),
                subject_label: manifest.fetch(:package_name), &
              )
            end
          end
        end
      end
    end
  end
end
