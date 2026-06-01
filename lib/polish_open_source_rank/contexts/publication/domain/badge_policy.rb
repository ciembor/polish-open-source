# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Domain
        # Builds public badge payloads for users, repositories, and organizations.
        class BadgePolicy
          def user_badges(profile:, language_badge: nil)
            country_rank = profile.fetch(:country_rank)
            city_badge = city_badge(profile)
            badges = []
            badges << ranked_badge('Polish Open Source', country_rank) if top?(country_rank, 100)
            badges << language_badge if language_badge
            badges << city_badge if city_badge
            badges.empty? ? [outside_ranking_badge] : badges
          end

          def user_badge(profile:, language_badge: nil)
            user_badges(profile: profile, language_badge: language_badge).first
          end

          def repository_badge(rank, language: nil)
            label = repository_label(language)
            return { label: label, value: Rank.place(rank), status: 'ranked', rank: rank } if rank

            { label: label, value: nil, status: 'outside_top_100', rank: rank }
          end

          def organization_badge(rank, city: nil, city_rank: nil)
            return { label: 'Polish Open Source Org', value: Rank.place(rank), status: 'ranked', rank: rank } if rank
            return ranked_badge("#{city} Org Elite", city_rank) if city && top?(city_rank, 10)
            return ranked_badge("#{city} Org Top 100", city_rank) if city && top?(city_rank, 100)

            { label: 'Polish Open Source Org', value: nil, status: 'outside_top_100', rank: rank }
          end

          def organization_repository_badge(rank, language: nil)
            label = repository_label(language)
            return { label: label, value: Rank.place(rank), status: 'ranked', rank: rank } if rank

            { label: label, value: nil, status: 'outside_top_100', rank: rank }
          end

          private

          def ranked_badge(label, rank)
            { label: label, value: Rank.place(rank), status: 'ranked', rank: rank }
          end

          def city_badge(profile)
            city = profile.fetch(:city)
            city_rank = profile.fetch(:city_rank)
            return ranked_badge("#{city} Elite", city_rank) if city && top?(city_rank, 10)

            ranked_badge("#{city} Top 100", city_rank) if city && top?(city_rank, 100)
          end

          def outside_ranking_badge
            { label: 'Polish Open Source', value: nil, status: 'outside_ranking', rank: nil }
          end

          def top?(rank, limit)
            rank && rank <= limit
          end

          def repository_label(language)
            return 'Polish Repo' unless language && !language.empty?

            LanguageBadgeLabel.repository(language)
          end
        end
      end
    end
  end
end
