# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        class MonthlySnapshotFactory
          def contributor_snapshot(period, source, profile, location, repository_metrics)
            Domain::ContributorSnapshot.new(
              **profile_snapshot_attributes(period, source, profile, location),
              public_repository_count: repository_metrics.public_repository_count,
              total_stars: repository_metrics.total_stars,
              monthly_stars_delta: repository_metrics.monthly_stars_delta,
              public_activity_count: source.public_activity_count(profile, period),
              merged_pull_requests_count: source.merged_pull_requests_count(profile, period)
            )
          end

          def contributor_profile(period, source, profile, location)
            Domain::ContributorSnapshot.new(
              **profile_snapshot_attributes(period, source, profile, location),
              public_repository_count: 0,
              total_stars: 0,
              monthly_stars_delta: 0,
              public_activity_count: 0,
              merged_pull_requests_count: 0
            )
          end

          def repository_snapshot(period, source, profile, location, repository, monthly_stars_delta)
            Domain::RepositorySnapshot.new(
              period: period,
              platform: source.platform,
              source_id: repository.fetch(:source_id),
              owner_source_id: profile.fetch(:source_id),
              owner_login: profile.fetch(:login),
              owner_city: location.city,
              owner_country: location.country,
              name: repository.fetch(:name),
              full_name: repository.fetch(:full_name),
              description: repository[:description],
              html_url: repository.fetch(:html_url),
              homepage: blank_to_nil(repository[:homepage]),
              language: repository[:language],
              fork: repository.fetch(:fork),
              archived: repository.fetch(:archived),
              stars: repository.fetch(:stars),
              monthly_stars_delta: monthly_stars_delta
            )
          end

          def organization_snapshot(period, source, profile, location, repository_metrics)
            Domain::OrganizationSnapshot.new(
              **profile_snapshot_attributes(period, source, profile, location),
              public_repository_count: repository_metrics.public_repository_count,
              total_stars: repository_metrics.total_stars,
              monthly_stars_delta: repository_metrics.monthly_stars_delta,
              members_count: source.organization_members_count(profile)
            )
          end

          def organization_profile(period, source, profile, location)
            Domain::OrganizationSnapshot.new(
              **profile_snapshot_attributes(period, source, profile, location),
              public_repository_count: 0,
              total_stars: 0,
              monthly_stars_delta: 0,
              members_count: 0
            )
          end

          def organization_repository_snapshot(period, source, profile, location, repository, monthly_stars_delta)
            Domain::OrganizationRepositorySnapshot.new(
              period: period,
              platform: source.platform,
              source_id: repository.fetch(:source_id),
              organization_source_id: profile.fetch(:source_id),
              organization_login: profile.fetch(:login),
              organization_city: location.city,
              organization_country: location.country,
              name: repository.fetch(:name),
              full_name: repository.fetch(:full_name),
              description: repository[:description],
              html_url: repository.fetch(:html_url),
              homepage: blank_to_nil(repository[:homepage]),
              language: repository[:language],
              fork: repository.fetch(:fork),
              archived: repository.fetch(:archived),
              stars: repository.fetch(:stars),
              monthly_stars_delta: monthly_stars_delta
            )
          end

          private

          def profile_snapshot_attributes(period, source, profile, location)
            {
              period: period,
              platform: source.platform,
              source_id: profile.fetch(:source_id),
              login: profile.fetch(:login),
              name: profile[:name],
              location_raw: location.raw,
              city: location.city,
              country: location.country,
              email: profile[:email],
              homepage: blank_to_nil(profile[:homepage]),
              html_url: profile.fetch(:html_url),
              avatar_url: profile[:avatar_url]
            }
          end

          def blank_to_nil(value)
            value if value.to_s.match?(/\S/)
          end
        end
      end
    end
  end
end
