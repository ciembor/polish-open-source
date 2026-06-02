# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # Discovers monthly user and organization candidates from source search APIs.
        class MonthlyCandidateDiscovery
          # Keeps one catalog term tied to the source and period being discovered.
          class Search
            def initialize(period:, source:, term:)
              @period = period
              @source = source
              @term = term
            end

            def user_log_line
              "[#{platform}] discovering users for location #{term.inspect}"
            end

            def organization_log_line
              "[#{platform}] discovering organizations for location #{term.inspect}"
            end

            def user_candidates
              source.search_users_by_location(term).map { |candidate| candidate_record(candidate) }
            end

            def organization_candidates
              source.search_organizations_by_location(term).map { |candidate| candidate_record(candidate) }
            end

            private

            attr_reader :period, :source, :term

            def candidate_record(candidate)
              CandidateRecord.new(
                period: period,
                platform: platform,
                source_query: term,
                candidate: candidate
              )
            end

            def platform
              source.platform
            end
          end

          # Records discovered candidate hashes without leaking table attributes upward.
          class CandidateRecord
            def initialize(period:, platform:, source_query:, candidate:)
              @period = period
              @platform = platform
              @source_query = source_query
              @candidate = candidate
            end

            def record_user_in(store)
              store.record_candidate(period, **attributes)
            end

            def record_organization_in(store)
              store.record_organization_candidate(period, **attributes)
            end

            private

            attr_reader :candidate, :period, :platform, :source_query

            def attributes
              {
                platform: platform,
                source_id: candidate.fetch(:source_id),
                login: candidate.fetch(:login),
                source_query: source_query
              }
            end
          end

          def initialize(store:, catalog:, logger:, store_mutex:)
            @store = store
            @catalog = catalog
            @logger = logger
            @store_mutex = store_mutex
          end

          def discover_users(period, source)
            catalog.search_terms.each do |term|
              discover_user_term(Search.new(period: period, source: source, term: term))
            end
            log(source, 'candidate discovery finished')
          end

          def discover_organizations(period, source)
            return unless source.supports_organizations?

            catalog.search_terms.each do |term|
              discover_organization_term(Search.new(period: period, source: source, term: term))
            end
            log(source, 'organization discovery finished')
          end

          private

          attr_reader :catalog, :logger, :store, :store_mutex

          def discover_user_term(search)
            logger.puts search.user_log_line
            search.user_candidates.each { |candidate| record_candidate(candidate) }
          end

          def discover_organization_term(search)
            logger.puts search.organization_log_line
            search.organization_candidates.each { |candidate| record_organization_candidate(candidate) }
          end

          def record_candidate(candidate)
            with_store do
              candidate.record_user_in(store)
            end
          end

          def record_organization_candidate(candidate)
            with_store do
              candidate.record_organization_in(store)
            end
          end

          def with_store(&)
            store_mutex.synchronize(&)
          end

          def log(source, message)
            logger.puts "[#{source.platform}] #{message}"
          end
        end
      end
    end
  end
end
