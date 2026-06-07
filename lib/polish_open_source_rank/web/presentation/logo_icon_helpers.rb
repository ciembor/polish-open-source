# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module LogoIconHelpers
        def logo_icon_exists?(path)
          icon_path = PolishOpenSourceRank.root.join('app/public', path.delete_prefix('/'))
          icon_path.file? && !icon_path.empty?
        end

        def logo_icon_initial(value)
          value.to_s.strip[0]&.upcase || '?'
        end
      end
    end
  end
end
