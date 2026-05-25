# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    class Composition
      def initialize(configuration:, github_oauth_client: nil, discord_oauth_client: nil, discord_gateway: nil,
                     discord_role_map: nil)
        @configuration = configuration
        @github_oauth_client = github_oauth_client
        @discord_oauth_client = discord_oauth_client
        @discord_gateway = discord_gateway
        @discord_role_map = discord_role_map
      end

      def github_oauth_client
        @github_oauth_client ||= Auth::GitHubOAuthClient.new(configuration)
      end

      def discord_oauth_client
        @discord_oauth_client ||= Auth::DiscordOAuthClient.new(configuration)
      end

      def discord_gateway
        @discord_gateway ||= Contexts::Community::Infrastructure::Discord::DiscordApiGateway.new(configuration)
      end

      def discord_role_map
        @discord_role_map ||= Contexts::Community::Infrastructure::Discord::DiscordRoleMap.new
      end

      def show_rankings
        @show_rankings ||= Contexts::Publication::Application::ShowRankings.new(ranking_read_model: ranking_read_model)
      end

      def show_ranking_detail
        @show_ranking_detail ||=
          Contexts::Publication::Application::ShowRankingDetail.new(ranking_read_model: ranking_read_model)
      end

      def list_editions
        @list_editions ||= Contexts::Publication::Application::ListEditions.new(edition_read_model: edition_read_model)
      end

      def show_user_profile
        @show_user_profile ||= Contexts::Publication::Application::ShowUserProfile.new(
          profile_read_model: profile_read_model
        )
      end

      def show_repository_profile
        @show_repository_profile ||=
          Contexts::Publication::Application::ShowRepositoryProfile.new(profile_read_model: profile_read_model)
      end

      def show_organization_profile
        @show_organization_profile ||=
          Contexts::Publication::Application::ShowOrganizationProfile.new(profile_read_model: profile_read_model)
      end

      def show_organization_repository_profile
        @show_organization_repository_profile ||=
          Contexts::Publication::Application::ShowOrganizationRepositoryProfile.new(
            profile_read_model: profile_read_model
          )
      end

      def show_package_index
        @show_package_index ||= Contexts::Packages::Application::ShowPackageIndex.new(
          package_ranking_read_model: package_ranking_read_model
        )
      end

      def show_package_ecosystem_rankings
        @show_package_ecosystem_rankings ||= Contexts::Packages::Application::ShowPackageEcosystemRankings.new(
          package_ranking_read_model: package_ranking_read_model
        )
      end

      def show_package_ranking_detail
        @show_package_ranking_detail ||= Contexts::Packages::Application::ShowPackageRankingDetail.new(
          package_ranking_read_model: package_ranking_read_model
        )
      end

      def show_package_profile
        @show_package_profile ||= Contexts::Packages::Application::ShowPackageProfile.new(
          package_ranking_read_model: package_ranking_read_model
        )
      end

      def show_language_index
        @show_language_index ||= Contexts::Languages::Application::ShowLanguageIndex.new(
          language_ranking_read_model: language_ranking_read_model
        )
      end

      def show_language
        @show_language ||= Contexts::Languages::Application::ShowLanguage.new(
          language_ranking_read_model: language_ranking_read_model
        )
      end

      def show_language_ranking_detail
        @show_language_ranking_detail ||= Contexts::Languages::Application::ShowLanguageRankingDetail.new(
          language_ranking_read_model: language_ranking_read_model
        )
      end

      def show_language_repository_ranking_detail
        @show_language_repository_ranking_detail ||=
          Contexts::Languages::Application::ShowLanguageRepositoryRankingDetail.new(
            language_ranking_read_model: language_ranking_read_model
          )
      end

      def render_badge
        @render_badge ||= Contexts::Publication::Application::RenderBadge.new(profile_read_model: profile_read_model)
      end

      def resolve_period
        @resolve_period ||= Contexts::Publication::Application::ResolvePeriod.new(
          period_read_model: cache_revision_read_model
        )
      end

      def show_job_progress
        @show_job_progress ||= Contexts::Operations::Application::ShowJobProgress.new(
          read_model: job_progress_read_model
        )
      end

      def show_discord_panel
        @show_discord_panel ||= Contexts::Community::Application::ShowDiscordPanel.new(
          connection_repository: discord_connection_repository,
          access_read_model: contributor_access_read_model
        )
      end

      def connect_discord_account
        @connect_discord_account ||= Contexts::Community::Application::ConnectDiscordAccount.new(
          profile_read_model: profile_read_model,
          connection_repository: discord_connection_repository,
          access_read_model: contributor_access_read_model,
          member_gateway: discord_gateway,
          role_map: discord_role_map
        )
      end

      def register_public_github_profile
        @register_public_github_profile ||= Contexts::Publication::Application::RegisterPublicGitHubProfile.new(
          profile_read_model: profile_read_model,
          profile_repository: public_profile_repository
        )
      end

      def cache_revision_read_model
        @cache_revision_read_model ||= Contexts::Publication::Infrastructure::SQLite::SQLiteCacheRevisionReadModel.new(
          database
        )
      end

      def ranking_read_model
        @ranking_read_model ||= Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingReadModel.new(database)
      end

      def edition_read_model
        @edition_read_model ||= Contexts::Publication::Infrastructure::SQLite::SQLiteEditionReadModel.new(
          database,
          ranking_read_model: ranking_read_model
        )
      end

      def profile_read_model
        @profile_read_model ||= Contexts::Publication::Infrastructure::SQLite::SQLiteProfileReadModel.new(database)
      end

      def package_ranking_read_model
        @package_ranking_read_model ||=
          Contexts::Packages::Infrastructure::SQLite::SQLitePackageRankingReadModel.new(database)
      end

      def language_ranking_read_model
        @language_ranking_read_model ||=
          Contexts::Languages::Infrastructure::SQLite::SQLiteLanguageRankingReadModel.new(database)
      end

      def public_profile_repository
        @public_profile_repository ||=
          Contexts::Publication::Infrastructure::SQLite::SQLitePublicProfileRepository.new(database)
      end

      def contributor_access_read_model
        @contributor_access_read_model ||=
          Contexts::Community::Infrastructure::SQLite::SQLiteContributorAccessReadModel.new(database)
      end

      def discord_connection_repository
        @discord_connection_repository ||=
          Contexts::Community::Infrastructure::SQLite::SQLiteDiscordConnectionRepository.new(database)
      end

      def job_progress_read_model
        @job_progress_read_model ||= Contexts::Operations::Infrastructure::SQLite::SQLiteJobProgressReadModel.new(
          database
        )
      end

      private

      attr_reader :configuration

      def database
        @database ||= begin
          db = Shared::Infrastructure::SQLite::Database.open(configuration.database_path)
          Infrastructure::PlatformSchemaMigration.new(db, Infrastructure::SQLiteSchema.sql).bootstrap!
          db
        end
      end
    end
  end
end
