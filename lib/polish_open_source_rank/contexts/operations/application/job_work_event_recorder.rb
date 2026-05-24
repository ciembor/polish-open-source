# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Application
        class JobWorkEventRecorder
          include TimedJobWorkEvents

          def record(**); end
        end
      end
    end
  end
end
