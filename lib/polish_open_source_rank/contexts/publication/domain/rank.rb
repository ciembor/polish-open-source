# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Domain
        class Rank
          def self.place(rank)
            "#{rank}#{ordinal_suffix(rank)}"
          end

          def self.ordinal_suffix(rank)
            return 'th' if (11..13).cover?(rank.to_i % 100)

            case rank.to_i % 10
            when 1 then 'st'
            when 2 then 'nd'
            when 3 then 'rd'
            else 'th'
            end
          end
        end
      end
    end
  end
end
