# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Application
        class DiscordInviteUseDetector
          def used_code(previous_uses, current_uses)
            changed_codes = increased_codes(previous_uses, current_uses) +
                            disappeared_codes(previous_uses, current_uses)
            changed_codes.uniq.one? ? changed_codes.first : nil
          end

          private

          def increased_codes(previous_uses, current_uses)
            current_uses.filter_map do |code, uses|
              code if uses.to_i > previous_uses.fetch(code, 0).to_i
            end
          end

          def disappeared_codes(previous_uses, current_uses)
            previous_uses.keys - current_uses.keys
          end
        end
      end
    end
  end
end
