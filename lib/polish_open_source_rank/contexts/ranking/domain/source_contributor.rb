# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        SourceContributor = Struct.new(
          :source_id,
          :login,
          :name,
          :location,
          :email,
          :homepage,
          :html_url,
          :avatar_url,
          keyword_init: true
        ) do
          include SourceRecord
        end
      end
    end
  end
end
