# frozen_string_literal: true

module PolishOpenSourceRank
  module Application
    class MonthlySnapshotJob
      BATCH_SIZE = 50

      def initialize(store:, github: nil, sources: nil, classifier: Domain::LocationClassifier.new,
                     catalog: Domain::LocationCatalog, logger: $stdout)
        @store = store
        @sources = sources || [github]
        @classifier = classifier
        @catalog = catalog
        @logger = logger
        @store_mutex = Mutex.new
        @log_mutex = Mutex.new
      end

      def call(period)
        run_id = store.create_run(period)
        return unless run_id

        discover_candidates(period)
        process_candidates(period)
        with_store { store.prune_rankings(period) }
        with_store { store.finish_run(run_id) }
      rescue StandardError => e
        with_store { store.fail_run(run_id, "#{e.class}: #{e.message}") } if run_id
        raise
      end

      private

      attr_reader :catalog, :classifier, :log_mutex, :logger, :sources, :store, :store_mutex

      def discover_candidates(period)
        run_sources_in_parallel('discover') { |source| discover_source_candidates(period, source) }
      end

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

      def process_candidates(period)
        run_sources_in_parallel('process') { |source| process_source_candidates(period, source) }
      end

      def process_source_candidates(period, source)
        loop do
          candidates = with_store { store.pending_candidates(period, platform: source.platform, limit: BATCH_SIZE) }
          break if candidates.empty?

          log(source, "processing #{candidates.length} candidates")
          candidates.each { |candidate| process_candidate(period, source, candidate) }
        end
        log(source, 'candidate processing finished')
      end

      def process_candidate(period, source, candidate)
        platform = candidate.fetch(:platform)
        login = candidate.fetch(:login)
        if with_store { store.processed_user?(period, platform, candidate.fetch(:source_id)) }
          return with_store { store.mark_candidate(period, platform, login, 'processed') }
        end

        process_unseen_candidate(period, source, login, candidate.fetch(:source_id))
      rescue SourceNotFound
        with_store { store.mark_candidate(period, platform, login, 'missing') }
      rescue StandardError => e
        with_store { store.mark_candidate(period, platform, login, 'failed', "#{e.class}: #{e.message}") }
        raise
      end

      def process_unseen_candidate(period, source, login, source_id)
        profile = source.user(login, source_id)
        location = classifier.call(profile[:location])
        return with_store { store.mark_candidate(period, source.platform, login, 'rejected') } unless location.polish?

        persist_profile(period, source, profile, location)
        with_store { store.mark_candidate(period, source.platform, login, 'processed') }
      end

      def persist_profile(period, source, profile, location)
        repositories = source.repositories_for(profile)
        repository_deltas = repository_deltas(source, repositories, period)

        with_store { store.upsert_user(user_attributes(source, profile, location)) }
        user_stats = user_stats_attributes(period, source, profile, location, repositories, repository_deltas)
        with_store { store.record_user_stats(user_stats) }
        persist_repositories(period, source, profile, location, repositories, repository_deltas)
      end

      def repository_deltas(source, repositories, period)
        repositories.to_h do |repository|
          [repository.fetch(:source_id), source.repository_stars_delta(repository, period)]
        end
      end

      def persist_repositories(period, source, profile, location, repositories, repository_deltas)
        repositories.each do |repository|
          with_store { store.upsert_repository(repository_attributes(source, profile, repository)) }
          with_store do
            store.record_repository_stats(repository_stats_attributes(period, source, profile, location, repository,
                                                                      repository_deltas))
          end
        end
      end

      def user_attributes(source, profile, location)
        {
          platform: source.platform,
          github_id: profile.fetch(:source_id),
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

      def user_stats_attributes(period, source, profile, location, repositories, repository_deltas)
        {
          period_start: period.start_date.to_s,
          platform: source.platform,
          user_github_id: profile.fetch(:source_id),
          login: profile.fetch(:login),
          city: location.city,
          country: location.country,
          public_repo_count: repositories.length,
          total_stars: repositories.sum { |repository| repository.fetch(:stars) },
          monthly_stars_delta: repository_deltas.values.sum,
          public_activity_count: source.public_activity_count(profile, period)
        }
      end

      def repository_attributes(source, profile, repository)
        {
          platform: source.platform,
          github_id: repository.fetch(:source_id),
          owner_github_id: profile.fetch(:source_id),
          owner_login: profile.fetch(:login),
          name: repository.fetch(:name),
          full_name: repository.fetch(:full_name),
          description: repository[:description],
          html_url: repository.fetch(:html_url),
          homepage: blank_to_nil(repository[:homepage]),
          language: repository[:language],
          fork: repository.fetch(:fork),
          archived: repository.fetch(:archived)
        }
      end

      def repository_stats_attributes(period, source, profile, location, repository, repository_deltas)
        {
          period_start: period.start_date.to_s,
          platform: source.platform,
          repository_github_id: repository.fetch(:source_id),
          owner_github_id: profile.fetch(:source_id),
          owner_login: profile.fetch(:login),
          owner_city: location.city,
          owner_country: location.country,
          stargazers_count: repository.fetch(:stars),
          monthly_stars_delta: repository_deltas.fetch(repository.fetch(:source_id))
        }
      end

      def candidate_login(candidate)
        candidate.fetch(:login)
      end

      def blank_to_nil(value)
        value.to_s.strip.empty? ? nil : value
      end

      def run_sources_in_parallel(stage)
        threads = sources.map do |source|
          Thread.new do
            yield source
          rescue StandardError => e
            log(source, "#{stage} failed: #{e.class}: #{e.message}")
            Thread.current[:error] = e
          end
        end
        threads.each(&:join)
        errors = threads.filter_map { |thread| thread[:error] }
        raise errors.first if errors.length == sources.length
      end

      def with_store(&)
        store_mutex.synchronize(&)
      end

      def log(source, message)
        log_mutex.synchronize do
          logger.puts "[#{source.platform}] #{message}"
          logger.flush if logger.respond_to?(:flush)
        end
      end
    end
  end
end
