# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module StructuredDataPageTypeHelpers
        private

        def about_page?
          @canonical_path == '/about'
        end

        def collection_page?
          structured_data_type == 'CollectionPage'
        end

        def profile_page?
          structured_data_type == 'ProfilePage'
        end

        def repository_page?
          structured_data_type == 'SoftwareSourceCode'
        end

        def city_scope?
          @scope && @scope.fetch(:slug) != 'poland'
        end

        def structured_data_type
          return 'AboutPage' if about_page?
          return 'SoftwareSourceCode' if repository_resource?
          return 'ProfilePage' if profile_resource?
          return 'CollectionPage' if collection_resource?

          'WebPage'
        end

        def collection_resource?
          @user_rankings || @editions || @ranking || package_collection?
        end

        def package_collection?
          @package_ecosystems || @package_rankings || @package_ranking
        end

        def package_page?
          package_collection?
        end

        def repository_resource?
          @repository || @organization_repository
        end

        def profile_resource?
          @profile || @organization
        end
      end
    end
  end
end
