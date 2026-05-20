# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        SourceRepository = Struct.new(
          :source_id,
          :name,
          :full_name,
          :description,
          :html_url,
          :homepage,
          :language,
          :fork,
          :archived,
          :stars,
          keyword_init: true
        ) do
          include SourceRecord
        end
      end
    end
  end
end
