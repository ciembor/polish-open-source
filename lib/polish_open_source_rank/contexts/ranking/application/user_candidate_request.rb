# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        class UserCandidateRequest < MonthlyCandidateRequest
          def work_attributes
            {
              stage: 'users',
              unit_kind: 'user_candidate',
              platform: platform,
              subject_id: source_id,
              subject_label: login
            }
          end

          def fetch_profile
            source.user(login, source_id)
          end

          def mark_user_candidate(store, status, error = nil)
            if error
              store.mark_candidate(period, platform, login, status, error)
            else
              store.mark_candidate(period, platform, login, status)
            end
          end
        end
      end
    end
  end
end
