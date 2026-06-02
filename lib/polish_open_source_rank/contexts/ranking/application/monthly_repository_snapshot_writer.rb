# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # Persists repository snapshots and returns monthly metrics for an accepted profile.
        class MonthlyRepositorySnapshotWriter
          def initialize(store:, store_mutex:, work_events:, minimum_repository_stars:,
                         snapshot_factory: MonthlySnapshotFactory.new)
            @store = store
            @store_mutex = store_mutex
            @work_events = work_events
            @minimum_repository_stars = minimum_repository_stars
            @snapshot_factory = snapshot_factory
          end

          def contributor_metrics(accepted_profile)
            repository_metrics(
              accepted_profile,
              collection: ContributorRepositoryCollection.new(accepted_profile)
            )
          end

          def organization_metrics(accepted_profile)
            repository_metrics(
              accepted_profile,
              collection: OrganizationRepositoryCollection.new(accepted_profile)
            )
          end

          private

          attr_reader :minimum_repository_stars, :snapshot_factory, :store, :store_mutex, :work_events

          def repository_metrics(accepted_profile, collection:)
            record_work_event(
              accepted_profile.period,
              collection.work_attributes
            ) do
              metrics = Domain::RepositoryMetrics.empty
              collection.each_repository do |repository|
                record_repository(accepted_profile, collection, repository, metrics)
              end
              metrics
            end
          end

          def record_repository(accepted_profile, collection, repository, metrics)
            record_work_event(
              accepted_profile.period,
              collection.repository_work_attributes(repository)
            ) do
              next 'skipped' unless repository.at_least_stars?(minimum_repository_stars)

              store_repository(accepted_profile, collection, repository, metrics)
            end
          end

          def store_repository(accepted_profile, collection, repository, metrics)
            star_snapshot = repository_star_snapshot(accepted_profile, repository) do
              collection.repository_delta(repository) { source_repository_delta(accepted_profile, repository) }
            end
            monthly_stars_delta = star_snapshot.fetch(:monthly_stars_delta)
            repository = repository.with_stars(star_snapshot.fetch(:stars))
            metrics.add(repository, monthly_stars_delta)
            with_store do
              collection.record_repository_snapshot(store, snapshot_factory, repository, monthly_stars_delta)
            end
            'stored'
          end

          def source_repository_delta(accepted_profile, repository)
            accepted_profile.source.repository_stars_delta(repository, accepted_profile.period)
          end

          def repository_star_snapshot(accepted_profile, repository)
            source = accepted_profile.source
            return source.repository_star_snapshot(repository, accepted_profile.period) if source.respond_to?(
              :repository_star_snapshot
            )

            {
              stars: repository.stars,
              monthly_stars_delta: yield
            }
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
            def initialize(accepted_profile)
              @accepted_profile = accepted_profile
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

            def repository_delta(repository)
              return 0 if repository.stars.zero?

              previous_stars = accepted_profile.previous_stars.contributor(
                accepted_profile.period, accepted_profile.source_platform, repository
              )
              if previous_stars && accepted_profile.use_snapshot_star_diff?
                return [repository.stars - previous_stars.to_i, 0].max
              end

              yield
            end

            def record_repository_snapshot(store, snapshot_factory, repository, monthly_stars_delta)
              store.record_repository_snapshot(
                snapshot_factory.repository_snapshot(
                  *accepted_profile.snapshot_args, repository, monthly_stars_delta
                )
              )
            end

            private

            attr_reader :accepted_profile
          end

          class OrganizationRepositoryCollection
            def initialize(accepted_profile)
              @accepted_profile = accepted_profile
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

            def repository_delta(repository)
              return 0 if repository.stars.zero?

              previous_stars = accepted_profile.previous_stars.organization(
                accepted_profile.period, accepted_profile.source_platform, repository
              )
              if previous_stars && accepted_profile.use_snapshot_star_diff?
                return [repository.stars - previous_stars.to_i, 0].max
              end

              yield
            end

            def record_repository_snapshot(store, snapshot_factory, repository, monthly_stars_delta)
              store.record_organization_repository_snapshot(
                snapshot_factory.organization_repository_snapshot(
                  *accepted_profile.snapshot_args, repository, monthly_stars_delta
                )
              )
            end

            private

            attr_reader :accepted_profile
          end
        end
      end
    end
  end
end
