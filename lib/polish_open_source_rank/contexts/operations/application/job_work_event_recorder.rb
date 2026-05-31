# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Application
        class JobWorkEventRecorder
          include TimedJobWorkEvents

          def initialize(heartbeat: nil)
            @heartbeat = heartbeat
            @completed_subject_ids = Set.new
          end

          def record(**); end

          def successful_subject_ids(_criteria)
            completed_subject_ids.dup
          end

          private

          attr_reader :completed_subject_ids, :heartbeat
        end
      end
    end
  end
end
