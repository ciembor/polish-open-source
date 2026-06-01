# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Domain
        # Produces compact user-facing labels for language leaderboard badges.
        class LanguageBadgeLabel
          CODES = {
            'C' => 'C',
            'C#' => 'CS',
            'C++' => 'CPP',
            'Elixir' => 'EX',
            'Go' => 'GO',
            'Java' => 'JAVA',
            'JavaScript' => 'JS',
            'Kotlin' => 'KT',
            'PHP' => 'PHP',
            'Python' => 'PY',
            'Ruby' => 'RB',
            'Rust' => 'RS',
            'Scala' => 'SC',
            'Shell' => 'SH',
            'Swift' => 'SW',
            'TypeScript' => 'TS'
          }.freeze

          def self.top_hundred(language)
            "Polish #{code(language)} Top 100"
          end

          def self.code(language)
            CODES.fetch(language.to_s) do
              fallback_code(language)
            end
          end

          def self.fallback_code(language)
            language.to_s.upcase.gsub(/[^A-Z0-9]+/, '')
          end
          private_class_method :fallback_code
        end
      end
    end
  end
end
