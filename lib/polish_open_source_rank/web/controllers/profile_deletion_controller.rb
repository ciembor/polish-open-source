# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module ProfileDeletionController
        private

        def delete_user_profile(platform, login)
          halt 403 unless valid_csrf_token?

          profile = deletion_profile(platform, login)
          publication.delete_public_profile.call(
            platform: profile.fetch(:platform),
            source_id: profile.fetch(:github_id)
          )
          redirect app_path(user_profile_path(profile)), 303
        end

        def deletion_profile(platform, login)
          profile = publication.show_user_profile.call(platform: platform, login: login, period_start: latest_period)
          halt 404 unless profile
          halt 403 unless own_profile?(profile)

          profile
        end
      end
    end
  end
end
