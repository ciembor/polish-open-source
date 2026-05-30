# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Application
        class JobWorkEventRecorder
          include TimedJobWorkEvents

          def initialize(heartbeat: nil)
            @heartbeat = heartbeat
          end

          def record(**); end

          private

          attr_reader :heartbeat
        end
      end
    end
  end
end
