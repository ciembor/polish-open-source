# frozen_string_literal: true

require 'uri'

module PolishOpenSourceRank
  module Web
    module Presentation
      class SafeExternalUrl
        def self.normalize(value)
          new(value).normalize
        end

        def initialize(value)
          @text = value.to_s.strip
        end

        def normalize
          uri = parsed_uri
          return nil unless safe_uri?(uri)

          uri.to_s
        end

        private

        attr_reader :text

        def parsed_uri
          return nil if text.empty? || text.match?(/[[:cntrl:]]/)

          URI.parse(text)
        rescue URI::InvalidURIError
          nil
        end

        def safe_uri?(uri)
          uri.is_a?(URI::HTTP) &&
            %w[http https].include?(uri.scheme) &&
            !uri.host.to_s.empty? &&
            uri.userinfo.nil?
        end
      end
    end
  end
end
