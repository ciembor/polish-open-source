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
            current_user.fetch(:github_id).to_i == repository_owner_id(repository).to_i
        end

        def repository_owner_id(repository)
          repository.fetch(:owner_github_id) { repository.fetch(:organization_github_id) }
        end

        def show_discord_panel_for(profile)
          community.show_discord_panel.call(
            platform: profile.fetch(:platform),
            source_id: profile.fetch(:github_id),
            period_start: @period
          )
        end

        def period_for(period_slug)
          period = publication.resolve_period.call(period_slug: period_slug)
          return period if period || period_slug == 'latest'

          halt 404
        end

        def latest_period
          publication.resolve_period.call(period_slug: 'latest')
        end

        def public_github_profile(login)
          publication.show_user_profile.call(platform: 'github', login: login, period_start: latest_period)
        end

        def auth_notice
          return @auth_notice if defined?(@auth_notice)

          @auth_notice = session.delete(:auth_notice)
        end

        def redirect_canonical_public_path(path)
          redirect app_path(localized_public_path(path, locale: current_locale, query: current_query)), 301
        end

        def redirect_to_canonical_profile_path(path)
          canonical_path = Localization::PublicPathPolicy.strip_locale_prefix(path)
          return if env.fetch('polish_open_source_rank.unlocalized_path', request.path_info) == canonical_path

          redirect app_path(localized_public_path(canonical_path, locale: current_locale, query: current_query)), 301
        end

        def assign_public_page(attributes) = attributes.each { |name, value| instance_variable_set("@#{name}", value) }

        def public_page_state = (@public_page_state ||= Presentation::PublicPageState.new(self))

        def ranking_paginator
          Presentation::RankingPaginator.new(params['page'])
        rescue Presentation::RankingPaginator::InvalidPage
          halt 404
        end

        def fetch_ranking_page(paginator, &)
          paginator.fetch(&)
        rescue Presentation::RankingPaginator::InvalidPage
          halt 404
        end
      end
    end
  end
end
