# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Domain
        class BadgePolicy
          def user_badge(rank, historical_top_ten:)
            return { label: 'Polish Elite', value: Rank.place(rank), status: 'ranked', rank: rank } if top?(rank, 10)

            value = historical_top_ten ? 'alumni' : 'contender'
            { label: 'Polish Elite', value: value, status: value }
          end

          def repository_badge(rank)
            return { label: 'Polish Repo', value: Rank.place(rank), status: 'ranked', rank: rank } if top?(rank, 100)

            { label: 'Polish Repo', value: nil, status: 'outside_top_100', rank: rank }
          end

          private

          def top?(rank, limit)
            rank && rank <= limit
          end
        end
      end
    end
  end
end
