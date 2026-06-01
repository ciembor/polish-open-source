# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          # Reads badge payloads that were frozen together with a public snapshot publication.
          class SQLitePublishedBadgeReadModel
            def initialize(database)
              @database = database
            end

            def badge(identity)
              period_start = identity.fetch(:period_start)
              return unless period_start

              row = database.fetch_all(<<~SQL, badge_params(identity)).first
                SELECT label, status, rank
                FROM published_badges
                WHERE period_start = ? AND badge_kind = ? AND platform = ? AND subject_github_id = ?
                LIMIT 1
              SQL
              row && badge_from(row)
            end

            private

            attr_reader :database

            def badge_params(identity)
              identity.values_at(:period_start, :kind, :platform, :subject_id)
            end

            def badge_from(row)
              rank = row[:rank]
              {
                label: row.fetch(:label),
                value: rank && Domain::Rank.place(rank),
                status: row.fetch(:status),
                rank: rank
              }
            end
          end
        end
      end
    end
  end
end
