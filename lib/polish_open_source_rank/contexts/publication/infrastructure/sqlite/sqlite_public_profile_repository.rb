# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          class SQLitePublicProfileRepository
            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def upsert_github_profile(attributes)
              identity = {
                platform: 'github',
                github_id: attributes.fetch(:github_id)
              }

              upsert(users_dataset, identity, {
                       platform: 'github',
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
                     })
            end

            def redact_profile(platform:, source_id:)
              users_dataset.where(platform: platform, github_id: source_id).update(
                name: nil,
                location_raw: nil,
                city: nil,
                country: nil,
                email: nil,
                homepage: nil,
                avatar_url: nil,
                avatar_hidden: 1,
                profile_deleted: 1,
                updated_at: timestamp
              )
            end

            private

            attr_reader :clock, :database

            def users_dataset
              database.dataset(:users)
            end

            def upsert(dataset, identity, attributes)
              scoped = dataset.where(identity)

              database.transaction do
                next unless update_profile(scoped, attributes, identity).zero?

                dataset.insert(attributes)
              end
            rescue Sequel::UniqueConstraintViolation
              database.write { update_profile(scoped, attributes, identity) }
            end

            def update_profile(scoped, attributes, identity)
              existing = scoped.first
              update = profile_update_attributes(attributes, identity, existing)

              scoped.update(update)
            end

            def profile_update_attributes(attributes, identity, existing)
              return attributes.slice(:login, :html_url, :updated_at) if deleted_profile?(existing)

              attributes.except(*identity.keys)
            end

            def deleted_profile?(record)
              record && record.fetch(:profile_deleted, 0).to_i == 1
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
