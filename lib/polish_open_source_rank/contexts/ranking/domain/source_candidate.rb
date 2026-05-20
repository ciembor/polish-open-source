# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        SourceCandidate = Struct.new(:source_id, :login, keyword_init: true) do
          include SourceRecord
        end
      end
    end
  end
end
