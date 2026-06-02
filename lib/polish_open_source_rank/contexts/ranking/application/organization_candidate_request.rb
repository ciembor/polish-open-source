# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        class OrganizationCandidateRequest < MonthlyCandidateRequest
          def work_attributes
            {
              stage: 'organizations',
              unit_kind: 'organization_candidate',
              platform: platform,
              subject_id: source_id,
              subject_label: login
            }
          end

          def fetch_profile
            source.organization(login, source_id)
          end

          def mark_organization_candidate(store, status, error = nil)
            if error
              store.mark_organization_candidate(period, platform, login, status, error)
            else
              store.mark_organization_candidate(period, platform, login, status)
            end
          end
        end
      end
    end
  end
end
