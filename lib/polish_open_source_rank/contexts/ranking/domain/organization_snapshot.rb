# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        OrganizationSnapshot = Struct.new(
          :period,
          :platform,
          :source_id,
          :login,
          :name,
          :location_raw,
          :city,
          :country,
          :email,
          :homepage,
          :html_url,
          :avatar_url,
          :public_repository_count,
          :total_stars,
          :monthly_stars_delta,
          :members_count,
          keyword_init: true
        )
      end
    end
  end
end
