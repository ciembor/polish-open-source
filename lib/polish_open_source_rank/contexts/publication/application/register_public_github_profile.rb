# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class RegisterPublicGitHubProfile
          class IneligibleLocation < StandardError
          end

          def initialize(profile_read_model:, profile_repository:, classifier: Contexts::Ranking::Domain::LocationClassifier.new)
            @profile_read_model = profile_read_model
            @profile_repository = profile_repository
            @classifier = classifier
          end

          def call(github_profile:, period_start:)
            profile = existing_profile(github_profile.fetch('login'), period_start)
            return profile if profile

            location = classifier.call(github_profile['location'])
            raise IneligibleLocation unless location.polish?

            profile_repository.upsert_github_profile(profile_attributes(github_profile, location))
            existing_profile(github_profile.fetch('login'), period_start)
          end

          private

          attr_reader :classifier, :profile_read_model, :profile_repository

          def existing_profile(login, period_start)
            profile_read_model.user_profile('github', login, period_start: period_start)
          end

          def profile_attributes(github_profile, location)
            {
              github_id: github_profile.fetch('id'),
              login: github_profile.fetch('login'),
              name: github_profile['name'],
              location_raw: location.raw,
              city: location.city,
              country: location.country,
              email: github_profile['email'],
              homepage: github_profile['homepage'],
              html_url: github_profile.fetch('html_url'),
              avatar_url: github_profile['avatar_url']
            }
          end
        end
      end
    end
  end
end
