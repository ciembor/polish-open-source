# frozen_string_literal: true

module PolishGithubRank
  module Application
    class MonthlySnapshotJob
      BATCH_SIZE = 50

      def initialize(store:, github:, classifier: Domain::LocationClassifier.new,
                     catalog: Domain::LocationCatalog, logger: $stdout)
        @store = store
        @github = github
        @classifier = classifier
        @catalog = catalog
        @logger = logger
      end

      def call(period)
        run_id = store.create_run(period)
        discover_candidates(period)
        process_candidates(period)
        store.finish_run(run_id)
      rescue StandardError => e
        store.fail_run(run_id, "#{e.class}: #{e.message}") if run_id
        raise
      end

      private

      attr_reader :catalog, :classifier, :github, :logger, :store

      def discover_candidates(period)
        catalog.search_terms.each do |term|
          logger.puts "Discovering GitHub users for location #{term.inspect}"
          github.search_users_by_location(term).each do |candidate|
            store.record_candidate(
              period,
              github_id: candidate.fetch('id'),
              login: candidate.fetch('login'),
              source_query: term
            )
          end
        end
      end

      def process_candidates(period)
        loop do
          candidates = store.pending_candidates(period, limit: BATCH_SIZE)
          break if candidates.empty?

          candidates.each { |candidate| process_candidate(period, candidate) }
        end
      end

      def process_candidate(period, candidate)
        login = candidate.fetch(:login)
        if store.processed_user?(period, candidate.fetch(:github_id))
          return store.mark_candidate(period, login, 'processed')
        end

        profile = github.user(login)
        location = classifier.call(profile['location'])
        return store.mark_candidate(period, login, 'rejected') unless location.polish?

        persist_profile(period, profile, location)
        store.mark_candidate(period, login, 'processed')
      rescue Infrastructure::GitHubClient::NotFound
        store.mark_candidate(period, candidate.fetch(:login), 'missing')
      rescue StandardError => e
        store.mark_candidate(period, candidate.fetch(:login), 'failed', "#{e.class}: #{e.message}")
        raise
      end

      def persist_profile(period, profile, location)
        repositories = github.repositories_for(profile.fetch('login'))
        repository_deltas = repository_deltas(repositories, period)

        store.upsert_user(user_attributes(profile, location))
        store.record_user_stats(user_stats_attributes(period, profile, location, repositories, repository_deltas))
        persist_repositories(period, profile, location, repositories, repository_deltas)
      end

      def repository_deltas(repositories, period)
        repositories.to_h do |repository|
          [repository.fetch('id'), github.repository_stars_delta(repository.fetch('full_name'), period)]
        end
      end

      def persist_repositories(period, profile, location, repositories, repository_deltas)
        repositories.each do |repository|
          store.upsert_repository(repository_attributes(profile, repository))
          store.record_repository_stats(repository_stats_attributes(period, profile, location, repository,
                                                                    repository_deltas))
        end
      end

      def user_attributes(profile, location)
        {
          github_id: profile.fetch('id'),
          login: profile.fetch('login'),
          name: profile['name'],
          location_raw: location.raw,
          city: location.city,
          country: location.country,
          email: profile['email'],
          homepage: blank_to_nil(profile['blog']),
          html_url: profile.fetch('html_url'),
          avatar_url: profile['avatar_url']
        }
      end

      def user_stats_attributes(period, profile, location, repositories, repository_deltas)
        {
          period_start: period.start_date.to_s,
          user_github_id: profile.fetch('id'),
          login: profile.fetch('login'),
          city: location.city,
          country: location.country,
          public_repo_count: repositories.length,
          total_stars: repositories.sum { |repository| repository.fetch('stargazers_count').to_i },
          monthly_stars_delta: repository_deltas.values.sum,
          public_activity_count: github.public_activity_count(profile.fetch('login'), period)
        }
      end

      def repository_attributes(profile, repository)
        {
          github_id: repository.fetch('id'),
          owner_github_id: profile.fetch('id'),
          owner_login: profile.fetch('login'),
          name: repository.fetch('name'),
          full_name: repository.fetch('full_name'),
          description: repository['description'],
          html_url: repository.fetch('html_url'),
          homepage: blank_to_nil(repository['homepage']),
          language: repository['language'],
          fork: repository.fetch('fork'),
          archived: repository.fetch('archived')
        }
      end

      def repository_stats_attributes(period, profile, location, repository, repository_deltas)
        {
          period_start: period.start_date.to_s,
          repository_github_id: repository.fetch('id'),
          owner_github_id: profile.fetch('id'),
          owner_login: profile.fetch('login'),
          owner_city: location.city,
          owner_country: location.country,
          stargazers_count: repository.fetch('stargazers_count').to_i,
          monthly_stars_delta: repository_deltas.fetch(repository.fetch('id'))
        }
      end

      def blank_to_nil(value)
        value.to_s.strip.empty? ? nil : value
      end
    end
  end
end
