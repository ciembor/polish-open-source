# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    class Composition
      # Wires operational read-only panels to their infrastructure adapters.
      class Operations
        def initialize(persistence:)
          @persistence = persistence
        end

        def show_job_progress
          @show_job_progress ||= Contexts::Operations::Application::ShowJobProgress.new(
            read_model: job_progress_read_model
          )
        end

        private

        attr_reader :persistence

        def job_progress_read_model
          @job_progress_read_model ||= Contexts::Operations::Infrastructure::SQLite::SQLiteJobProgressReadModel.new(
            persistence.database
          )
        end
      end
    end
  end
end
