# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # rubocop:disable Metrics/ClassLength
        class RunMonthlySnapshot
          BATCH_SIZE = 50

          def initialize(store:, github: nil, sources: nil, classifier: Domain::LocationClassifier.new,
                         catalog: Domain::LocationCatalog, logger: $stdout)
            @store = store
            @sources = sources || [github]
            @classifier = classifier
            @catalog = catalog
            @logger = logger
            @store_mutex = Mutex.new
          end

          def call(period, refresh: false, scope: nil)
            @scope = scope
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

          attr_reader :catalog, :classifier, :logger, :sources, :store, :store_mutex

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
              candidates.each { |candidate| process_candidate(period, source, candidate, refresh: refresh) }
            end
            log(source, 'candidate processing finished')
          end

          def process_source_organizations(period, source, refresh:)
            return unless source.supports_organizations?

            loop do
              candidates = with_store do
                store.pending_organization_candidates(period, platform: source.platform, limit: BATCH_SIZE)
              end
              break if candidates.empty?

              log(source, "processing #{candidates.length} organizations")
              candidates.each do |candidate|
                process_organization_candidate(period, source, candidate, refresh: refresh)
              end
            end
            log(source, 'organization processing finished')
          end

          def process_candidate(period, source, candidate, refresh:)
            platform = candidate.fetch(:platform)
            login = candidate.fetch(:login)
            if !refresh && with_store { store.processed_user?(period, platform, candidate.fetch(:source_id)) }
              return with_store { store.mark_candidate(period, platform, login, 'processed') }
            end

            process_unseen_candidate(period, source, login, candidate.fetch(:source_id))
          rescue SourceNotFound
            with_store { store.mark_candidate(period, platform, login, 'missing') }
          rescue StandardError => e
            with_store { store.mark_candidate(period, platform, login, 'failed', "#{e.class}: #{e.message}") }
            log(source, "candidate #{login.inspect} failed: #{e.class}: #{e.message}")
          end

          def process_unseen_candidate(period, source, login, source_id)
            profile = source.user(login, source_id)
            location = classifier.call(profile[:location])
            unless location.polish?
              return with_store { store.mark_candidate(period, source.platform, login, 'rejected') }
            end

            persist_profile(period, source, profile, location)
            with_store { store.mark_candidate(period, source.platform, login, 'processed') }
          end

          def process_organization_candidate(period, source, candidate, refresh:)
            platform = candidate.fetch(:platform)
            login = candidate.fetch(:login)
            if !refresh && with_store { store.processed_organization?(period, platform, candidate.fetch(:source_id)) }
              return with_store { store.mark_organization_candidate(period, platform, login, 'processed') }
            end

            process_unseen_organization_candidate(period, source, login, candidate.fetch(:source_id))
          rescue SourceNotFound
            with_store { store.mark_organization_candidate(period, platform, login, 'missing') }
          rescue StandardError => e
            with_store do
              store.mark_organization_candidate(period, platform, login, 'failed', "#{e.class}: #{e.message}")
            end
            log(source, "organization #{login.inspect} failed: #{e.class}: #{e.message}")
          end

          def process_unseen_organization_candidate(period, source, login, source_id)
            profile = source.organization(login, source_id)
            location = classifier.call(profile[:location])
            unless location.polish?
              return with_store { store.mark_organization_candidate(period, source.platform, login, 'rejected') }
            end

            persist_organization_profile(period, source, profile, location)
            with_store { store.mark_organization_candidate(period, source.platform, login, 'processed') }
          end

          def persist_profile(period, source, profile, location)
            with_store { store.record_contributor_profile(contributor_profile(period, source, profile, location)) }
            repository_metrics = persist_repositories(period, source, profile, location)

            snapshot = contributor_snapshot(period, source, profile, location, repository_metrics)
            with_store { store.record_contributor_snapshot(snapshot) }
          end

          def persist_organization_profile(period, source, profile, location)
            with_store { store.record_organization_profile(organization_profile(period, source, profile, location)) }
            repository_metrics = persist_organization_repositories(period, source, profile, location)

            snapshot = organization_snapshot(period, source, profile, location, repository_metrics)
            with_store { store.record_organization_snapshot(snapshot) }
          end

          def repository_delta(source, repository, period)
            current_stars = repository.fetch(:stars)
            return 0 if current_stars.zero?

            previous_stars = with_store do
              store.previous_repository_stars(period, source.platform, repository.fetch(:source_id))
            end
            return [current_stars - previous_stars.to_i, 0].max if previous_stars

            source.repository_stars_delta(repository, period)
          end

          def organization_repository_delta(source, repository, period)
            current_stars = repository.fetch(:stars)
            return 0 if current_stars.zero?

            previous_stars = with_store do
              store.previous_organization_repository_stars(period, source.platform, repository.fetch(:source_id))
            end
            return [current_stars - previous_stars.to_i, 0].max if previous_stars

            source.repository_stars_delta(repository, period)
          end

          def persist_repositories(period, source, profile, location)
            metrics = Domain::RepositoryMetrics.empty
            each_repository_for(source, profile) do |repository|
              monthly_stars_delta = repository_delta(source, repository, period)
              metrics.add(repository, monthly_stars_delta)
              with_store do
                store.record_repository_snapshot(
                  repository_snapshot(period, source, profile, location, repository, monthly_stars_delta)
                )
              end
            end
            metrics
          end

          def persist_organization_repositories(period, source, profile, location)
            metrics = Domain::RepositoryMetrics.empty
            each_organization_repository_for(source, profile) do |repository|
              monthly_stars_delta = organization_repository_delta(source, repository, period)
              metrics.add(repository, monthly_stars_delta)
              with_store do
                store.record_organization_repository_snapshot(
                  organization_repository_snapshot(period, source, profile, location, repository, monthly_stars_delta)
                )
              end
            end
            metrics
          end

          def contributor_snapshot(period, source, profile, location, repository_metrics)
            Domain::ContributorSnapshot.new(
              **profile_snapshot_attributes(period, source, profile, location),
              public_repository_count: repository_metrics.public_repository_count,
              total_stars: repository_metrics.total_stars,
              monthly_stars_delta: repository_metrics.monthly_stars_delta,
              public_activity_count: source.public_activity_count(profile, period)
            )
          end

          def contributor_profile(period, source, profile, location)
            Domain::ContributorSnapshot.new(
              **profile_snapshot_attributes(period, source, profile, location),
              public_repository_count: 0,
              total_stars: 0,
              monthly_stars_delta: 0,
              public_activity_count: 0
            )
          end

          def repository_snapshot(period, source, profile, location, repository, monthly_stars_delta)
            Domain::RepositorySnapshot.new(
              period: period,
              platform: source.platform,
              source_id: repository.fetch(:source_id),
              owner_source_id: profile.fetch(:source_id),
              owner_login: profile.fetch(:login),
              owner_city: location.city,
              owner_country: location.country,
              name: repository.fetch(:name),
              full_name: repository.fetch(:full_name),
              description: repository[:description],
              html_url: repository.fetch(:html_url),
              homepage: blank_to_nil(repository[:homepage]),
              language: repository[:language],
              fork: repository.fetch(:fork),
              archived: repository.fetch(:archived),
              stars: repository.fetch(:stars),
              monthly_stars_delta: monthly_stars_delta
            )
          end

          def organization_snapshot(period, source, profile, location, repository_metrics)
            Domain::OrganizationSnapshot.new(
              **profile_snapshot_attributes(period, source, profile, location),
              public_repository_count: repository_metrics.public_repository_count,
              total_stars: repository_metrics.total_stars,
              monthly_stars_delta: repository_metrics.monthly_stars_delta
            )
          end

          def organization_profile(period, source, profile, location)
            Domain::OrganizationSnapshot.new(
              **profile_snapshot_attributes(period, source, profile, location),
              public_repository_count: 0,
              total_stars: 0,
              monthly_stars_delta: 0
            )
          end

          def organization_repository_snapshot(period, source, profile, location, repository, monthly_stars_delta)
            Domain::OrganizationRepositorySnapshot.new(
              period: period,
              platform: source.platform,
              source_id: repository.fetch(:source_id),
              organization_source_id: profile.fetch(:source_id),
              organization_login: profile.fetch(:login),
              organization_city: location.city,
              organization_country: location.country,
              name: repository.fetch(:name),
              full_name: repository.fetch(:full_name),
              description: repository[:description],
              html_url: repository.fetch(:html_url),
              homepage: blank_to_nil(repository[:homepage]),
              language: repository[:language],
              fork: repository.fetch(:fork),
              archived: repository.fetch(:archived),
              stars: repository.fetch(:stars),
              monthly_stars_delta: monthly_stars_delta
            )
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

          def profile_snapshot_attributes(period, source, profile, location)
            {
              period: period,
              platform: source.platform,
              source_id: profile.fetch(:source_id),
              login: profile.fetch(:login),
              name: profile[:name],
              location_raw: location.raw,
              city: location.city,
              country: location.country,
              email: profile[:email],
              homepage: blank_to_nil(profile[:homepage]),
              html_url: profile.fetch(:html_url),
              avatar_url: profile[:avatar_url]
            }
          end

          def candidate_login(candidate)
            candidate.fetch(:login)
          end

          def blank_to_nil(value)
            value if value.to_s.match?(/\S/)
          end

          def run_source_snapshots(period, refresh_platforms:)
            threads = sources.map do |source|
              Thread.new { run_source_snapshot(period, source, refresh: refresh_platforms.include?(source.platform)) }
            end
            threads.each(&:join)
            errors = threads.filter_map { |thread| thread[:error] }
            raise errors.first if errors.length == sources.length
          end

          def complete_run(period, run_id)
            return store.fail_run(run_id, 'Retryable candidates remain') if source_retryable_candidates?(period)
            return if store.retryable_candidates?(period)

            store.prune_rankings(period)
            store.finish_run(run_id)
          end

          def source_retryable_candidates?(period)
            store.retryable_candidates?(
              period,
              platforms: sources.map(&:platform),
              candidate_types: active_candidate_types
            )
          end

          def active_candidate_types
            case @scope
            when :users
              [:users]
            when :organizations
              [:organizations]
            else
              %i[users organizations]
            end
          end

          def run_source_snapshot(period, source, refresh:)
            errors = []
            errors.concat(run_user_source_snapshot(period, source, refresh: refresh)) unless @scope == :organizations
            errors.concat(run_organization_source_snapshot(period, source, refresh: refresh)) unless @scope == :users
            Thread.current[:error] = errors.compact.first
          end

          def run_user_source_snapshot(period, source, refresh:)
            [
              run_source_stage(source, 'process existing candidates') do
                process_source_candidates(period, source, refresh: refresh)
              end,
              run_source_stage(source, 'discover') { discover_source_candidates(period, source) },
              run_source_stage(source, 'process') { process_source_candidates(period, source, refresh: refresh) }
            ]
          end

          def run_organization_source_snapshot(period, source, refresh:)
            [
              run_source_stage(source, 'process existing organizations') do
                process_source_organizations(period, source, refresh: refresh)
              end,
              run_source_stage(source, 'discover organizations') { discover_source_organizations(period, source) },
              run_source_stage(source, 'process organizations') do
                process_source_organizations(period, source, refresh: refresh)
              end
            ]
          end

          def run_source_stage(source, stage)
            yield
            nil
          rescue StandardError => e
            log(source, "#{stage} failed: #{e.class}: #{e.message}")
            e
          end

          def with_store(&)
            store_mutex.synchronize(&)
          end

          def log(source, message)
            logger.puts "[#{source.platform}] #{message}"
            logger.flush if logger.respond_to?(:flush)
          end
        end
        # rubocop:enable Metrics/ClassLength
      end
    end
  end
end
