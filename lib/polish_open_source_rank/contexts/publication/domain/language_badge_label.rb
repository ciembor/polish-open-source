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

          EXTENSIONS = {
            'C' => '.c',
            'C#' => '.cs',
            'C++' => '.cpp',
            'Elixir' => '.ex',
            'Go' => '.go',
            'Java' => '.java',
            'JavaScript' => '.js',
            'Kotlin' => '.kt',
            'PHP' => '.php',
            'Python' => '.py',
            'Ruby' => '.rb',
            'Rust' => '.rs',
            'Scala' => '.scala',
            'Shell' => '.sh',
            'Swift' => '.swift',
            'TypeScript' => '.ts'
          }.freeze

          def self.top_hundred(language)
            "Polish #{code(language)} Top 100"
          end

          def self.repository(language)
            "Polish #{extension(language)} Repo"
          end

          def self.code(language)
            CODES.fetch(language.to_s) do
              fallback_code(language)
            end
          end

          def self.extension(language)
            EXTENSIONS.fetch(language.to_s) do
              ".#{fallback_extension(language)}"
            end
          end

          def self.fallback_code(language)
            language.to_s.upcase.gsub(/[^A-Z0-9]+/, '')
          end
          private_class_method :fallback_code

          def self.fallback_extension(language)
            language.to_s.downcase.gsub(/[^a-z0-9]+/, '')
          end
          private_class_method :fallback_extension
        end
      end
    end
  end
end
