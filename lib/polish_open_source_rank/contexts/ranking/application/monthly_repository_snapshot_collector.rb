# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # Collects repository snapshots for an accepted profile and returns monthly metrics.
        class MonthlyRepositorySnapshotCollector
          MINIMUM_REPOSITORY_STARS = 5

          def initialize(store:, store_mutex:, work_events:, minimum_repository_stars: MINIMUM_REPOSITORY_STARS,
                         snapshot_factory: MonthlySnapshotFactory.new,
                         star_snapshot_policy: MonthlyRepositoryStarSnapshotPolicy.new)
            @store = store
            @store_mutex = store_mutex
            @work_events = work_events
            @minimum_repository_stars = minimum_repository_stars
            @snapshot_factory = snapshot_factory
            @star_snapshot_policy = star_snapshot_policy
          end

          def contributor_metrics(accepted_profile)
            repository_metrics(ContributorRepositoryCollection.new(accepted_profile, star_snapshot_policy))
          end

          def organization_metrics(accepted_profile)
            repository_metrics(OrganizationRepositoryCollection.new(accepted_profile, star_snapshot_policy))
          end

          private

          attr_reader :minimum_repository_stars, :snapshot_factory, :star_snapshot_policy, :store, :store_mutex,
                      :work_events

          def repository_metrics(collection)
            record_work_event(collection.accepted_profile.period, collection.work_attributes) do
              metrics = Domain::RepositoryMetrics.empty
              collection.each_repository { |repository| record_repository(collection, repository, metrics) }
              metrics
            end
          end

          def record_repository(collection, repository, metrics)
            record_work_event(collection.accepted_profile.period, collection.repository_work_attributes(repository)) do
              next 'skipped' unless repository.at_least_stars?(minimum_repository_stars)

              store_repository(collection, repository, metrics)
            end
          end

          def store_repository(collection, repository, metrics)
            star_snapshot = collection.star_snapshot(repository)
            monthly_stars_delta = star_snapshot.fetch(:monthly_stars_delta)
            repository = repository.with_stars(star_snapshot.fetch(:stars))
            metrics.add(repository, monthly_stars_delta)
            with_store do
              collection.record_repository_snapshot(store, snapshot_factory, repository, monthly_stars_delta)
            end
            'stored'
          end

          def record_work_event(period, attributes, &)
            work_events.record_timed(
              period_start: period.start_date.to_s,
              job_kind: 'monthly',
              **attributes, &
            )
          end

          def with_store(&)
            store_mutex.synchronize(&)
          end

          class ContributorRepositoryCollection
            attr_reader :accepted_profile

            def initialize(accepted_profile, star_snapshot_policy)
              @accepted_profile = accepted_profile
              @star_snapshot_policy = star_snapshot_policy
            end

            def work_attributes
              {
                stage: 'user_repositories',
                unit_kind: 'user_repository_collection',
                platform: accepted_profile.source_platform,
                subject_id: accepted_profile.profile.source_id,
                subject_label: accepted_profile.profile.login
              }
            end

            def repository_work_attributes(repository)
              {
                stage: 'user_repository',
                unit_kind: 'repository',
                platform: accepted_profile.source_platform,
                subject_id: repository.source_id,
                subject_label: repository.full_name
              }
            end

            def each_repository(&)
              source = accepted_profile.source
              return source.each_repository_for(accepted_profile.profile, &) if source.respond_to?(:each_repository_for)

              source.repositories_for(accepted_profile.profile).each(&)
            end

            def star_snapshot(repository)
              star_snapshot_policy.snapshot(accepted_profile, repository, previous_stars_role: :contributor)
            end

            def record_repository_snapshot(store, snapshot_factory, repository, monthly_stars_delta)
              store.record_repository_snapshot(
                snapshot_factory.repository_snapshot(
                  *accepted_profile.snapshot_args, repository, monthly_stars_delta
                )
              )
            end

            private

            attr_reader :star_snapshot_policy
          end

          class OrganizationRepositoryCollection
            attr_reader :accepted_profile

            def initialize(accepted_profile, star_snapshot_policy)
              @accepted_profile = accepted_profile
              @star_snapshot_policy = star_snapshot_policy
            end

            def work_attributes
              {
                stage: 'organization_repositories',
                unit_kind: 'organization_repository_collection',
                platform: accepted_profile.source_platform,
                subject_id: accepted_profile.profile.source_id,
                subject_label: accepted_profile.profile.login
              }
            end

            def repository_work_attributes(repository)
              {
                stage: 'organization_repository',
                unit_kind: 'repository',
                platform: accepted_profile.source_platform,
                subject_id: repository.source_id,
                subject_label: repository.full_name
              }
            end

            def each_repository(&)
              source = accepted_profile.source
              if source.respond_to?(:each_repository_for_organization)
                return source.each_repository_for_organization(accepted_profile.profile, &)
              end

              source.repositories_for_organization(accepted_profile.profile).each(&)
            end

            def star_snapshot(repository)
              star_snapshot_policy.snapshot(accepted_profile, repository, previous_stars_role: :organization)
            end

            def record_repository_snapshot(store, snapshot_factory, repository, monthly_stars_delta)
              store.record_organization_repository_snapshot(
                snapshot_factory.organization_repository_snapshot(
                  *accepted_profile.snapshot_args, repository, monthly_stars_delta
                )
              )
            end

            private

            attr_reader :star_snapshot_policy
          end
        end
      end
    end
  end
end
