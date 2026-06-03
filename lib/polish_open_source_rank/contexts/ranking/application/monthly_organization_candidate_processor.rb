# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        class MonthlyOrganizationCandidateProcessor < MonthlyCandidateProcessor
          def process(period, source, candidate, refresh:)
            request = OrganizationCandidateRequest.new(period, source, candidate, refresh)
            record_work_event(request) { process_request(request) }
          end

          private

          def process_request(request)
            return mark_processed(request) if processed_candidate?(request)

            profile = request.fetch_profile
            location = classifier.without_foreign_countries(profile.location_evidence)
            return mark_rejected(request) unless location.polish?

            profile_writer.record_organization(request.accepted_profile(profile_writer, profile, location))
            mark_processed(request)
          rescue SourceNotFound
            mark_missing(request)
          rescue StandardError => e
            mark_failed(request, e)
          end

          def processed_candidate?(request)
            return false if request.refresh?

            with_store { store.processed_organization?(request.period, request.platform, request.source_id) }
          end

          def mark_processed(request)
            with_store { request.mark_organization_candidate(store, 'processed') }
            'processed'
          end

          def mark_missing(request)
            with_store { request.mark_organization_candidate(store, 'missing') }
            'missing'
          end

          def mark_rejected(request)
            with_store { request.mark_organization_candidate(store, 'rejected') }
            'rejected'
          end

          def mark_failed(request, error)
            error_message = "#{error.class}: #{error.message}"
            with_store { request.mark_organization_candidate(store, 'failed', error_message) }
            logger.puts "[#{request.platform}] organization #{request.login.inspect} failed: #{error_message}"
            'failed'
          end
        end
      end
    end
  end
end
