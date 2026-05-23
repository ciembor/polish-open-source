# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Domain
        class BadgePolicy
          def user_badges(country_rank:, city:, city_rank:)
            [user_badge(country_rank: country_rank, city: city, city_rank: city_rank)]
          end

          def user_badge(country_rank:, city:, city_rank:)
            return ranked_badge('Polish Open Source', country_rank) if top?(country_rank, 100)
            return ranked_badge("#{city} Elite", city_rank) if city && top?(city_rank, 10)
            return ranked_badge("#{city} Top 100", city_rank) if city && top?(city_rank, 100)

            { label: 'Polish Open Source', value: nil, status: 'outside_ranking', rank: nil }
          end

          def repository_badge(rank)
            return { label: 'Polish Repo', value: Rank.place(rank), status: 'ranked', rank: rank } if rank

            { label: 'Polish Repo', value: nil, status: 'outside_top_100', rank: rank }
          end

          def organization_badge(rank, city: nil, city_rank: nil)
            return { label: 'Polish Open Source Org', value: Rank.place(rank), status: 'ranked', rank: rank } if rank
            return ranked_badge("#{city} Org Elite", city_rank) if city && top?(city_rank, 10)
            return ranked_badge("#{city} Org Top 100", city_rank) if city && top?(city_rank, 100)

            { label: 'Polish Open Source Org', value: nil, status: 'outside_top_100', rank: rank }
          end

          def organization_repository_badge(rank)
            return { label: 'Polish Org Repo', value: Rank.place(rank), status: 'ranked', rank: rank } if rank

            { label: 'Polish Org Repo', value: nil, status: 'outside_top_100', rank: rank }
          end

          private

          def ranked_badge(label, rank)
            { label: label, value: Rank.place(rank), status: 'ranked', rank: rank }
          end

          def top?(rank, limit)
            rank && rank <= limit
          end
        end
      end
    end
  end
end
