# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # Persists accepted monthly contributor and organization profile snapshots.
        class MonthlyProfileSnapshotWriter
          # Carries the accepted source profile and run options across snapshot writers.
          class AcceptedProfile
            def initialize(period:, source:, profile:, location:)
              @period = period
              @source = source
              @profile = profile
              @location = location
            end

            attr_reader :location, :period, :profile, :source

            def snapshot_args
              [period, source, profile, location]
            end

            def source_platform
              source.platform
            end
          end

          def initialize(store:, store_mutex:, snapshot_factory:, repository_collector:)
            @store = store
            @store_mutex = store_mutex
            @snapshot_factory = snapshot_factory
            @repository_collector = repository_collector
          end

          def accepted_profile(period:, source:, profile:, location:)
            AcceptedProfile.new(
              period: period,
              source: source,
              profile: profile,
              location: location
            )
          end

          def record_contributor(accepted_profile)
            with_store do
              store.record_contributor_profile(snapshot_factory.contributor_profile(*accepted_profile.snapshot_args))
            end
            metrics = repository_collector.contributor_metrics(accepted_profile)
            snapshot = snapshot_factory.contributor_snapshot(*accepted_profile.snapshot_args, metrics)
            with_store { store.record_contributor_snapshot(snapshot) }
          end

          def record_organization(accepted_profile)
            profile_snapshot = snapshot_factory.organization_profile(*accepted_profile.snapshot_args)
            with_store { store.record_organization_profile(profile_snapshot) }
            metrics = repository_collector.organization_metrics(accepted_profile)
            snapshot = snapshot_factory.organization_snapshot(*accepted_profile.snapshot_args, metrics)
            with_store { store.record_organization_snapshot(snapshot) }
          end

          private

          attr_reader :repository_collector, :snapshot_factory, :store, :store_mutex

          def with_store(&)
            store_mutex.synchronize(&)
          end
        end
      end
    end
  end
end
