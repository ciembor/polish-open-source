# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module PublicRepositoryKind
        SLUGS = {
          'users' => 'user',
          'organizations' => 'organization'
        }.freeze

        module_function

        def key_for_slug(slug)
          SLUGS.fetch(slug.to_s)
        end
      end
    end
  end
end
