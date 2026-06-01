# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    # Calculates the freshness token for public HTML responses from view, asset, and locale files.
    class HtmlRevision
      WATCHED_PATTERNS = [
        'app/views/**/*.erb',
        'app/public/css/**/*.css',
        'app/public/js/**/*.js'
      ].freeze

      def initialize(root:)
        @root = root
      end

      def value(locale:)
        latest_mtime(watched_paths(locale))
      end

      private

      attr_reader :root

      def watched_paths(locale)
        WATCHED_PATTERNS.flat_map { |pattern| root.glob(pattern) } +
          [root.join("config/locales/#{locale}.yml")]
      end

      def latest_mtime(paths)
        paths.select(&:file?).map { |path| path.mtime.to_i }.max
      end
    end
  end
end
