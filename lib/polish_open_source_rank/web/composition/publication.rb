# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    class Composition
      # Wires public ranking and profile use cases to publication-facing adapters.
      class Publication
        def initialize(read_models:)
          @read_models = read_models
        end

        def show_rankings
          @show_rankings ||= Contexts::Publication::Application::ShowRankings.new(
            ranking_read_model: read_models.public_ranking
          )
        end

        def show_ranking_detail
          @show_ranking_detail ||=
            Contexts::Publication::Application::ShowRankingDetail.new(ranking_read_model: read_models.public_ranking)
        end

        def list_editions
          @list_editions ||= Contexts::Publication::Application::ListEditions.new(
            edition_read_model: read_models.edition
          )
        end

        def show_user_profile
          @show_user_profile ||= Contexts::Publication::Application::ShowUserProfile.new(
            profile_read_model: read_models.profile
          )
        end

        def show_repository_profile
          @show_repository_profile ||=
            Contexts::Publication::Application::ShowRepositoryProfile.new(profile_read_model: read_models.profile)
        end

        def show_organization_profile
          @show_organization_profile ||=
            Contexts::Publication::Application::ShowOrganizationProfile.new(profile_read_model: read_models.profile)
        end

        def show_organization_repository_profile
          @show_organization_repository_profile ||=
            Contexts::Publication::Application::ShowOrganizationRepositoryProfile.new(
              profile_read_model: read_models.profile
            )
        end

        def render_badge
          @render_badge ||= Contexts::Publication::Application::RenderBadge.new(profile_read_model: read_models.profile)
        end

        def resolve_period
          @resolve_period ||= Contexts::Publication::Application::ResolvePeriod.new(
            period_read_model: read_models.cache_revision
          )
        end

        def register_public_github_profile
          @register_public_github_profile ||= Contexts::Publication::Application::RegisterPublicGitHubProfile.new(
            profile_read_model: read_models.profile,
            profile_repository: read_models.public_profile_repository
          )
        end

        def cache_revision
          @cache_revision ||= PublicCacheRevision.new(read_model: read_models.cache_revision)
        end

        private

        attr_reader :read_models
      end
    end
  end
end
