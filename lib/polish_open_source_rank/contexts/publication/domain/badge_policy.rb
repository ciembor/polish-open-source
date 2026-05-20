# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Domain
        class BadgePolicy
          def user_badges(rank, historical_top_ten:, historical_top_hundred:)
            [
              elite_badge(rank, historical_top_ten),
              top_hundred_badge(rank, historical_top_hundred)
            ].compact
          end

          def user_badge(rank, historical_top_ten:, historical_top_hundred: false)
            user_badges(
              rank,
              historical_top_ten: historical_top_ten,
              historical_top_hundred: historical_top_hundred
            ).first
          end

          def repository_badge(rank)
            return { label: 'Polish Repo', value: Rank.place(rank), status: 'ranked', rank: rank } if rank

            { label: 'Polish Repo', value: nil, status: 'outside_top_100', rank: rank }
          end

          private

          def elite_badge(rank, historical_top_ten)
            return { label: 'Polish Elite', value: Rank.place(rank), status: 'ranked', rank: rank } if top?(rank, 10)
            return unless historical_top_ten && !top?(rank, 100)

            { label: 'Polish Elite', value: 'ex', status: 'ex', rank: rank }
          end

          def top_hundred_badge(rank, historical_top_hundred)
            return { label: 'Polish Top 100', value: Rank.place(rank), status: 'ranked', rank: rank } if top?(rank, 100)
            return unless historical_top_hundred

            { label: 'Polish Top 100', value: 'ex', status: 'ex', rank: rank }
          end

          def top?(rank, limit)
            rank && rank <= limit
          end
        end
      end
    end
  end
end
