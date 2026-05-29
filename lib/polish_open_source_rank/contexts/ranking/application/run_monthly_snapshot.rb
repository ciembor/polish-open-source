# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        class RunMonthlySnapshot
          include MonthlySnapshotWorkflow

          BATCH_SIZE = 50
          MINIMUM_REPOSITORY_STARS = 5
          def initialize(store:, sources:, classifier: Domain::LocationClassifier.new,
                         catalog: Domain::LocationCatalog, logger: $stdout,
                         work_events: Operations::Application::JobWorkEventRecorder.new)
            @store = store
            @sources = sources
            @classifier = classifier
            @catalog = catalog
            @logger = logger
            @store_mutex = Mutex.new
            @work_events = work_events
            @snapshot_factory = MonthlySnapshotFactory.new
          end

          def call(period, refresh: false, scope: nil, recalculate_stars: false, existing_only: false)
            @scope = scope
            @recalculate_stars = recalculate_stars
            @existing_only = existing_only
            refresh_platforms = refresh ? sources.map(&:platform) : []
            run_id = store.create_run(period, refresh_platforms: refresh_platforms)
            return unless run_id

            run_source_snapshots(period, refresh_platforms: refresh_platforms)

            complete_run(period, run_id)
          rescue StandardError => e
            store.fail_run(run_id, "#{e.class}: #{e.message}") if run_id
            raise
          end

          private

          attr_reader :catalog, :classifier, :logger, :snapshot_factory, :sources, :store, :store_mutex, :work_events

          def discover_source_candidates(period, source)
            catalog.search_terms.each do |term|
              log(source, "discovering users for location #{term.inspect}")
              source.search_users_by_location(term).each do |candidate|
                with_store do
                  store.record_candidate(
                    period,
                    platform: source.platform,
                    source_id: candidate.fetch(:source_id),
                    login: candidate_login(candidate),
                    source_query: term
                  )
                end
              end
            end
            log(source, 'candidate discovery finished')
          end

          def discover_source_organizations(period, source)
            return unless source.supports_organizations?

            catalog.search_terms.each do |term|
              log(source, "discovering organizations for location #{term.inspect}")
              source.search_organizations_by_location(term).each do |candidate|
                with_store do
                  store.record_organization_candidate(
                    period,
                    platform: source.platform,
                    source_id: candidate.fetch(:source_id),
                    login: candidate_login(candidate),
                    source_query: term
                  )
                end
              end
            end
            log(source, 'organization discovery finished')
          end

          def process_source_candidates(period, source, refresh:)
            loop do
              candidates = with_store { store.pending_candidates(period, platform: source.platform, limit: BATCH_SIZE) }
              break if candidates.empty?

              log(source, "processing #{candidates.length} candidates")
              candidates.each do |candidate|
                record_work_event(
                  period,
                  job_kind: 'monthly',
                  stage: 'users',
                  unit_kind: 'user_candidate',
                  platform: source.platform,
                  subject_id: candidate.fetch(:source_id),
                  subject_label: candidate.fetch(:login)
                ) do
                  process_candidate(period, source, candidate, refresh: refresh)
                end
              end
            end
            log(source, 'candidate processing finished')
          end

          def process_source_organizations(period, source, refresh:)
            return unless source.supports_organizations?

            loop do
              candidates = pending_organization_candidates(period, source)
              break if candidates.empty?

              log(source, "processing #{candidates.length} organizations")
              candidates.each do |candidate|
                record_work_event(
                  period,
                  job_kind: 'monthly',
                  stage: 'organizations',
                  unit_kind: 'organization_candidate',
                  platform: source.platform,
                  subject_id: candidate.fetch(:source_id),
                  subject_label: candidate.fetch(:login)
                ) do
                  process_organization_candidate(period, source, candidate, refresh: refresh)
                end
              end
            end
            log(source, 'organization processing finished')
          end

          def pending_organization_candidates(period, source)
            with_store do
              store.pending_organization_candidates(period, platform: source.platform, limit: BATCH_SIZE)
            end
          end

          def process_candidate(period, source, candidate, refresh:)
            platform = candidate.fetch(:platform)
            login = candidate.fetch(:login)
            if !refresh && with_store { store.processed_user?(period, platform, candidate.fetch(:source_id)) }
              with_store { store.mark_candidate(period, platform, login, 'processed') }
              return 'processed'
            end

            process_unseen_candidate(period, source, login, candidate.fetch(:source_id))
          rescue SourceNotFound
            with_store { store.mark_candidate(period, platform, login, 'missing') }
            'missing'
          rescue StandardError => e
            with_store { store.mark_candidate(period, platform, login, 'failed', "#{e.class}: #{e.message}") }
            log(source, "candidate #{login.inspect} failed: #{e.class}: #{e.message}")
            'failed'
          end

          def process_unseen_candidate(period, source, login, source_id)
            profile = source.user(login, source_id)
            location = classifier.call(profile[:location])
            unless location.polish?
              with_store { store.mark_candidate(period, source.platform, login, 'rejected') }
              return 'rejected'
            end

            persist_profile(period, source, profile, location)
            with_store { store.mark_candidate(period, source.platform, login, 'processed') }
            'processed'
          end

          def process_organization_candidate(period, source, candidate, refresh:)
            platform = candidate.fetch(:platform)
            login = candidate.fetch(:login)
            if !refresh && with_store { store.processed_organization?(period, platform, candidate.fetch(:source_id)) }
              with_store { store.mark_organization_candidate(period, platform, login, 'processed') }
              return 'processed'
            end

            process_unseen_organization_candidate(period, source, login, candidate.fetch(:source_id))
          rescue SourceNotFound
            with_store { store.mark_organization_candidate(period, platform, login, 'missing') }
            'missing'
          rescue StandardError => e
            with_store do
              store.mark_organization_candidate(period, platform, login, 'failed', "#{e.class}: #{e.message}")
            end
            log(source, "organization #{login.inspect} failed: #{e.class}: #{e.message}")
            'failed'
          end

          def process_unseen_organization_candidate(period, source, login, source_id)
            profile = source.organization(login, source_id)
            location = classifier.call(profile[:location])
            unless location.polish?
              with_store { store.mark_organization_candidate(period, source.platform, login, 'rejected') }
              return 'rejected'
            end

            persist_organization_profile(period, source, profile, location)
            with_store { store.mark_organization_candidate(period, source.platform, login, 'processed') }
            'processed'
          end

          def persist_profile(period, source, profile, location)
            with_store do
              store.record_contributor_profile(snapshot_factory.contributor_profile(period, source, profile, location))
            end
            repository_metrics = persist_repositories(period, source, profile, location)

            snapshot = snapshot_factory.contributor_snapshot(period, source, profile, location, repository_metrics)
            with_store { store.record_contributor_snapshot(snapshot) }
          end

          def persist_organization_profile(period, source, profile, location)
            profile_snapshot = snapshot_factory.organization_profile(period, source, profile, location)
            with_store { store.record_organization_profile(profile_snapshot) }
            repository_metrics = persist_organization_repositories(period, source, profile, location)

            snapshot = snapshot_factory.organization_snapshot(period, source, profile, location, repository_metrics)
            with_store { store.record_organization_snapshot(snapshot) }
          end

          def repository_delta(source, repository, period)
            current_stars = repository.fetch(:stars)
            return 0 if current_stars.zero?

            previous_stars = with_store do
              store.previous_repository_stars(period, source.platform, repository.fetch(:source_id))
            end
            return [current_stars - previous_stars.to_i, 0].max if previous_stars && !recalculate_stars?

            source.repository_stars_delta(repository, period)
          end

          def organization_repository_delta(source, repository, period)
            current_stars = repository.fetch(:stars)
            return 0 if current_stars.zero?

            previous_stars = with_store do
              store.previous_organization_repository_stars(period, source.platform, repository.fetch(:source_id))
            end
            return [current_stars - previous_stars.to_i, 0].max if previous_stars && !recalculate_stars?

            source.repository_stars_delta(repository, period)
          end

          def persist_repositories(period, source, profile, location)
            record_work_event(
              period,
              job_kind: 'monthly',
              stage: 'user_repositories',
              unit_kind: 'user_repository_collection',
              platform: source.platform,
              subject_id: profile.fetch(:source_id),
              subject_label: profile.fetch(:login)
            ) do
              metrics = Domain::RepositoryMetrics.empty
              each_repository_for(source, profile) do |repository|
                persist_repository(period, source, profile, location, repository, metrics)
              end
              metrics
            end
          end

          def persist_organization_repositories(period, source, profile, location)
            record_work_event(
              period,
              job_kind: 'monthly',
              stage: 'organization_repositories',
              unit_kind: 'organization_repository_collection',
              platform: source.platform,
              subject_id: profile.fetch(:source_id),
              subject_label: profile.fetch(:login)
            ) do
              metrics = Domain::RepositoryMetrics.empty
              each_organization_repository_for(source, profile) do |repository|
                persist_organization_repository(period, source, profile, location, repository, metrics)
              end
              metrics
            end
          end

          def persist_repository(period, source, profile, location, repository, metrics)
            record_work_event(
              period,
              job_kind: 'monthly',
              stage: 'user_repository',
              unit_kind: 'repository',
              platform: source.platform,
              subject_id: repository.fetch(:source_id),
              subject_label: repository.fetch(:full_name)
            ) do
              next 'skipped' unless catalog_repository?(repository)

              store_repository(period, source, profile, location, repository, metrics)
            end
          end

          def store_repository(period, source, profile, location, repository, metrics)
            stars = repository_star_snapshot(source, repository, period) do
              repository_delta(source, repository, period)
            end
            repository = repository_with_stars(repository, stars.fetch(:stars))
            metrics.add(repository, stars.fetch(:monthly_stars_delta))
            with_store do
              store.record_repository_snapshot(
                snapshot_factory.repository_snapshot(
                  period, source, profile, location, repository, stars.fetch(:monthly_stars_delta)
                )
              )
            end
            'stored'
          end

          def persist_organization_repository(period, source, profile, location, repository, metrics)
            record_work_event(
              period,
              job_kind: 'monthly',
              stage: 'organization_repository',
              unit_kind: 'repository',
              platform: source.platform,
              subject_id: repository.fetch(:source_id),
              subject_label: repository.fetch(:full_name)
            ) do
              next 'skipped' unless catalog_repository?(repository)

              store_organization_repository(period, source, profile, location, repository, metrics)
            end
          end

          def store_organization_repository(period, source, profile, location, repository, metrics)
            stars = repository_star_snapshot(source, repository, period) do
              organization_repository_delta(source, repository, period)
            end
            repository = repository_with_stars(repository, stars.fetch(:stars))
            metrics.add(repository, stars.fetch(:monthly_stars_delta))
            with_store do
              store.record_organization_repository_snapshot(
                snapshot_factory.organization_repository_snapshot(
                  period, source, profile, location, repository, stars.fetch(:monthly_stars_delta)
                )
              )
            end
            'stored'
          end

          def repository_star_snapshot(source, repository, period)
            return source.repository_star_snapshot(repository, period) if source.respond_to?(:repository_star_snapshot)

            {
              stars: repository.fetch(:stars),
              monthly_stars_delta: yield
            }
          end

          def repository_with_stars(repository, stars)
            repository.to_h.merge(stars: stars)
          end

          def catalog_repository?(repository)
            repository.fetch(:stars) >= MINIMUM_REPOSITORY_STARS
          end

          def each_repository_for(source, profile, &)
            return source.each_repository_for(profile, &) if source.respond_to?(:each_repository_for)

            source.repositories_for(profile).each(&)
          end

          def each_organization_repository_for(source, profile, &)
            if source.respond_to?(:each_repository_for_organization)
              return source.each_repository_for_organization(profile, &)
            end

            source.repositories_for_organization(profile).each(&)
          end

          def candidate_login(candidate)
            candidate.fetch(:login)
          end

          def recalculate_stars?
            @recalculate_stars
          end

          def with_store(&)
            store_mutex.synchronize(&)
          end

          def log(source, message)
            logger.puts "[#{source.platform}] #{message}"
            logger.flush if logger.respond_to?(:flush)
          end

          def record_work_event(period, attributes, &)
            work_events.record_timed(
              period_start: period.start_date.to_s,
              **attributes, &
            )
          end
        end
      end
    end
  end
end
