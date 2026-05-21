# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module SharedController
        private

        def current_user
          session[:current_user]&.transform_keys(&:to_sym)
        end

        def own_profile?(profile)
          current_user &&
            current_user.fetch(:platform) == profile.fetch(:platform) &&
            current_user.fetch(:github_id).to_i == profile.fetch(:github_id).to_i
        end

        def own_repository?(repository)
          current_user &&
            current_user.fetch(:platform) == repository.fetch(:platform) &&
            current_user.fetch(:github_id).to_i == repository.fetch(:owner_github_id).to_i
        end

        def show_discord_panel_for(profile)
          show_discord_panel.call(
            platform: profile.fetch(:platform),
            source_id: profile.fetch(:github_id),
            period_start: @period
          )
        end

        def period_for(period_slug)
          period = resolve_period.call(period_slug: period_slug)
          return period if period || period_slug == 'latest'

          halt 404
        end

        def latest_period
          resolve_period.call(period_slug: 'latest')
        end

        def ranked_github_profile(login)
          profile = show_user_profile.call(platform: 'github', login: login, period_start: latest_period)
          profile if profile && profile[:period_start]
        end
      end
    end
  end
end
