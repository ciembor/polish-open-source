# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        RepositorySnapshot = Struct.new(
          :period,
          :platform,
          :source_id,
          :owner_source_id,
          :owner_login,
          :owner_city,
          :owner_country,
          :name,
          :full_name,
          :description,
          :html_url,
          :homepage,
          :language,
          :fork,
          :archived,
          :stars,
          :monthly_stars_delta,
          keyword_init: true
        )
      end
    end
  end
end
