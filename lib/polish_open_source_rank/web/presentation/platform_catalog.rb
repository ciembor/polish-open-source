# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      class PlatformCatalog
        PLATFORMS = {
          'codeberg' => { name: 'Codeberg', icon_path: '/icons/codeberg.svg' },
          'github' => { name: 'GitHub', icon_path: '/icons/github.svg' },
          'gitlab' => { name: 'GitLab', icon_path: '/icons/gitlab.svg' }
        }.freeze

        DEFAULT_PLATFORM = 'github'

        def name(platform)
          platform_data(platform).fetch(:name)
        end

        def icon_path(platform)
          platform_data(platform).fetch(:icon_path)
        end

        private

        def platform_data(platform)
          PLATFORMS.fetch(platform, PLATFORMS.fetch(DEFAULT_PLATFORM))
        end
      end
    end
  end
end
