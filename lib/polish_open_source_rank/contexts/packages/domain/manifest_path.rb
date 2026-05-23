# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        ManifestPath = Struct.new(:ecosystem, :path, keyword_init: true)
      end
    end
  end
end
