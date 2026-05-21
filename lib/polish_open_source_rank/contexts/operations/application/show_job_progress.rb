# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Application
        class ShowJobProgress
          def initialize(read_model:)
            @read_model = read_model
          end

          def call(now: Time.now.utc)
            read_model.job_progress(now: now)
          end

          private

          attr_reader :read_model
        end
      end
    end
  end
end
