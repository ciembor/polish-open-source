# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # Persists accepted monthly contributor and organization profile snapshots.
        class MonthlyProfileSnapshotWriter
          # Carries the accepted source profile and run options across snapshot writers.
          class AcceptedProfile
            def initialize(period:, source:, profile:, location:, use_snapshot_star_diff:, previous_stars:)
              @period = period
              @source = source
              @profile = profile
              @location = location
              @use_snapshot_star_diff = use_snapshot_star_diff
              @previous_stars = previous_stars
            end

            attr_reader :location, :period, :previous_stars, :profile, :source

            def snapshot_args
              [period, source, profile, location]
            end

            def source_platform
              source.platform
            end

            def use_snapshot_star_diff?
              @use_snapshot_star_diff
            end
          end

          def initialize(store:, store_mutex:, work_events:, minimum_repository_stars:,
                         snapshot_factory: MonthlySnapshotFactory.new)
            @store = store
            @store_mutex = store_mutex
            @snapshot_factory = snapshot_factory
            @repository_writer = MonthlyRepositorySnapshotWriter.new(
              store: store,
              store_mutex: store_mutex,
              work_events: work_events,
              minimum_repository_stars: minimum_repository_stars,
              snapshot_factory: snapshot_factory
            )
          end

          def accepted_profile(period:, source:, profile:, location:, use_snapshot_star_diff:)
            AcceptedProfile.new(
              period: period,
              source: source,
              profile: profile,
              location: location,
              use_snapshot_star_diff: use_snapshot_star_diff,
              previous_stars: PreviousRepositoryStars.new(store, store_mutex)
            )
          end

          def record_contributor(accepted_profile)
            with_store do
              store.record_contributor_profile(snapshot_factory.contributor_profile(*accepted_profile.snapshot_args))
            end
            metrics = repository_writer.contributor_metrics(accepted_profile)
            snapshot = snapshot_factory.contributor_snapshot(*accepted_profile.snapshot_args, metrics)
            with_store { store.record_contributor_snapshot(snapshot) }
          end

          def record_organization(accepted_profile)
            profile_snapshot = snapshot_factory.organization_profile(*accepted_profile.snapshot_args)
            with_store { store.record_organization_profile(profile_snapshot) }
            metrics = repository_writer.organization_metrics(accepted_profile)
            snapshot = snapshot_factory.organization_snapshot(*accepted_profile.snapshot_args, metrics)
            with_store { store.record_organization_snapshot(snapshot) }
          end

          private

          attr_reader :repository_writer, :snapshot_factory, :store, :store_mutex

          def with_store(&)
            store_mutex.synchronize(&)
          end

          class PreviousRepositoryStars
            def initialize(store, store_mutex)
              @store = store
              @store_mutex = store_mutex
            end

            def contributor(period, platform, repository)
              with_store do
                store.previous_repository_stars(period, platform, repository.source_id)
              end
            end

            def organization(period, platform, repository)
              with_store do
                store.previous_organization_repository_stars(period, platform, repository.source_id)
              end
            end

            private

            attr_reader :store, :store_mutex

            def with_store(&)
              store_mutex.synchronize(&)
            end
          end
        end
      end
    end
  end
end
