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

            private

            attr_reader :clock, :database

            def users_dataset
              database.dataset(:users)
            end

            def upsert(dataset, identity, attributes)
              scoped = dataset.where(identity)

              database.transaction do
                next unless scoped.update(attributes.except(*identity.keys)).zero?

                dataset.insert(attributes)
              end
            rescue Sequel::UniqueConstraintViolation
              scoped.update(attributes.except(*identity.keys))
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
