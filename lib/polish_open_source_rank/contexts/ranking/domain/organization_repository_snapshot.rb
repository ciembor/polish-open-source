# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        OrganizationRepositorySnapshot = Struct.new(
          :period,
          :platform,
          :source_id,
          :organization_source_id,
          :organization_login,
          :organization_city,
          :organization_country,
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
