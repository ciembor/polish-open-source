# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          class SQLiteSnapshotRecordMapper
            def initialize(clock:)
              @clock = clock
            end

            def contributor_attributes(snapshot)
              identity_attributes(snapshot)
            end

            def contributor_stats_attributes(snapshot)
              {
                period_start: snapshot.period.start_date.to_s,
                platform: snapshot.platform,
                user_github_id: snapshot.source_id,
                login: snapshot.login,
                city: snapshot.city,
                country: snapshot.country,
                public_repo_count: snapshot.public_repository_count,
                total_stars: snapshot.total_stars,
                monthly_stars_delta: snapshot.monthly_stars_delta,
                merged_pull_requests_count: snapshot.merged_pull_requests_count
              }
            end

            def organization_attributes(snapshot)
              identity_attributes(snapshot)
            end

            def organization_stats_attributes(snapshot)
              {
                period_start: snapshot.period.start_date.to_s,
                platform: snapshot.platform,
                organization_github_id: snapshot.source_id,
                login: snapshot.login,
                city: snapshot.city,
                country: snapshot.country,
                public_repo_count: snapshot.public_repository_count,
                total_stars: snapshot.total_stars,
                monthly_stars_delta: snapshot.monthly_stars_delta,
                members_count: snapshot.members_count
              }
            end

            def repository_attributes(snapshot)
              {
                platform: snapshot.platform,
                github_id: snapshot.source_id,
                owner_github_id: snapshot.owner_source_id,
                owner_login: snapshot.owner_login,
                name: snapshot.name,
                full_name: snapshot.full_name,
                description: snapshot.description,
                html_url: snapshot.html_url,
                homepage: snapshot.homepage,
                language: snapshot.language,
                fork: snapshot.fork,
                archived: snapshot.archived
              }
            end

            def repository_stats_attributes(snapshot)
              {
                period_start: snapshot.period.start_date.to_s,
                platform: snapshot.platform,
                repository_github_id: snapshot.source_id,
                owner_github_id: snapshot.owner_source_id,
                owner_login: snapshot.owner_login,
                owner_city: snapshot.owner_city,
                owner_country: snapshot.owner_country,
                stargazers_count: snapshot.stars,
                monthly_stars_delta: snapshot.monthly_stars_delta
              }
            end

            def organization_repository_attributes(snapshot)
              {
                platform: snapshot.platform,
                github_id: snapshot.source_id,
                organization_github_id: snapshot.organization_source_id,
                organization_login: snapshot.organization_login,
                name: snapshot.name,
                full_name: snapshot.full_name,
                description: snapshot.description,
                html_url: snapshot.html_url,
                homepage: snapshot.homepage,
                language: snapshot.language,
                fork: snapshot.fork,
                archived: snapshot.archived
              }
            end

            def organization_repository_stats_attributes(snapshot)
              {
                period_start: snapshot.period.start_date.to_s,
                platform: snapshot.platform,
                repository_github_id: snapshot.source_id,
                organization_github_id: snapshot.organization_source_id,
                organization_login: snapshot.organization_login,
                organization_city: snapshot.organization_city,
                organization_country: snapshot.organization_country,
                stargazers_count: snapshot.stars,
                monthly_stars_delta: snapshot.monthly_stars_delta
              }
            end

            def user_record(attributes)
              identity_record(attributes)
            end

            def user_stats_record(attributes)
              {
                period_start: attributes.fetch(:period_start),
                platform: attributes.fetch(:platform, 'github'),
                user_github_id: attributes.fetch(:user_github_id),
                login: attributes.fetch(:login),
                city: attributes[:city],
                country: attributes[:country],
                public_repo_count: attributes.fetch(:public_repo_count),
                total_stars: attributes.fetch(:total_stars),
                monthly_stars_delta: attributes.fetch(:monthly_stars_delta),
                merged_pull_requests_count: attributes[:merged_pull_requests_count].to_i,
                updated_at: timestamp
              }
            end

            def organization_record(attributes)
              identity_record(attributes)
            end

            def organization_stats_record(attributes)
              {
                period_start: attributes.fetch(:period_start),
                platform: attributes.fetch(:platform, 'github'),
                organization_github_id: attributes.fetch(:organization_github_id),
                login: attributes.fetch(:login),
                city: attributes[:city],
                country: attributes[:country],
                public_repo_count: attributes.fetch(:public_repo_count),
                total_stars: attributes.fetch(:total_stars),
                monthly_stars_delta: attributes.fetch(:monthly_stars_delta),
                members_count: attributes[:members_count].to_i,
                updated_at: timestamp
              }
            end

            def repository_record(attributes)
              repository_identity_record(attributes).merge(
                owner_github_id: attributes.fetch(:owner_github_id),
                owner_login: attributes.fetch(:owner_login)
              )
            end

            def repository_stats_record(attributes, updated_at)
              {
                period_start: attributes.fetch(:period_start),
                platform: attributes.fetch(:platform, 'github'),
                repository_github_id: attributes.fetch(:repository_github_id),
                owner_github_id: attributes.fetch(:owner_github_id),
                owner_login: attributes.fetch(:owner_login),
                owner_city: attributes[:owner_city],
                owner_country: attributes[:owner_country],
                stargazers_count: attributes.fetch(:stargazers_count),
                monthly_stars_delta: attributes.fetch(:monthly_stars_delta),
                updated_at: updated_at
              }
            end

            def organization_repository_record(attributes)
              repository_identity_record(attributes).merge(
                organization_github_id: attributes.fetch(:organization_github_id),
                organization_login: attributes.fetch(:organization_login)
              )
            end

            def organization_repository_stats_record(attributes, updated_at)
              {
                period_start: attributes.fetch(:period_start),
                platform: attributes.fetch(:platform, 'github'),
                repository_github_id: attributes.fetch(:repository_github_id),
                organization_github_id: attributes.fetch(:organization_github_id),
                organization_login: attributes.fetch(:organization_login),
                organization_city: attributes[:organization_city],
                organization_country: attributes[:organization_country],
                stargazers_count: attributes.fetch(:stargazers_count),
                monthly_stars_delta: attributes.fetch(:monthly_stars_delta),
                updated_at: updated_at
              }
            end

            private

            attr_reader :clock

            def identity_attributes(snapshot)
              {
                platform: snapshot.platform,
                github_id: snapshot.source_id,
                login: snapshot.login,
                name: snapshot.name,
                location_raw: snapshot.location_raw,
                city: snapshot.city,
                country: snapshot.country,
                email: snapshot.email,
                homepage: snapshot.homepage,
                html_url: snapshot.html_url,
                avatar_url: snapshot.avatar_url
              }
            end

            def identity_record(attributes)
              {
                platform: attributes.fetch(:platform, 'github'),
                github_id: attributes.fetch(:github_id),
                login: attributes.fetch(:login),
                name: attributes[:name],
                location_raw: attributes[:location_raw],
                city: attributes[:city],
                country: attributes[:country],
                email: attributes[:email],
                homepage: attributes[:homepage],
                html_url: attributes.fetch(:html_url),
                avatar_url: attributes[:avatar_url],
                updated_at: timestamp
              }
            end

            def repository_identity_record(attributes)
              {
                platform: attributes.fetch(:platform, 'github'),
                github_id: attributes.fetch(:github_id),
                name: attributes.fetch(:name),
                full_name: attributes.fetch(:full_name),
                description: attributes[:description],
                html_url: attributes.fetch(:html_url),
                homepage: attributes[:homepage],
                language: attributes[:language],
                fork: boolean_int(attributes.fetch(:fork)),
                archived: boolean_int(attributes.fetch(:archived)),
                updated_at: timestamp
              }
            end

            def boolean_int(value)
              value ? 1 : 0
            end

            def timestamp
              clock.call.iso8601
            end
          end
        end
      end
    end
  end
end
