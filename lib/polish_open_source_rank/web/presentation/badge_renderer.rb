# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      class BadgeRenderer
        def svg(badge, home_url:)
          labels = labels_for(badge)
          width = labels.fetch(:left_width) + labels.fetch(:right_width)
          <<~SVG
            <svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="20" role="img" aria-label="#{labels.fetch(:aria)}">
              <title>#{Rack::Utils.escape_html(labels.fetch(:aria))}</title>
              #{defs(width)}
              <a href="#{Rack::Utils.escape_html(home_url)}" target="_blank">
                #{background(labels.fetch(:left_width), labels.fetch(:right_width), width)}
                #{text(labels)}
              </a>
            </svg>
          SVG
        end

        private

        def labels_for(badge)
          left = badge.fetch(:label)
          right = badge[:value].to_s
          {
            left: left,
            right: right,
            left_width: segment_width(left),
            right_width: right.empty? ? 20 : segment_width(right),
            aria: [left, right].reject(&:empty?).join(' ')
          }
        end

        def segment_width(text)
          [(text.length * 7) + 12, 20].max
        end

        def defs(width)
          <<~SVG
            <linearGradient id="s" x2="0" y2="100%">
              <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
              <stop offset="1" stop-opacity=".1"/>
            </linearGradient>
            <clipPath id="r"><rect width="#{width}" height="20" rx="3" fill="#fff"/></clipPath>
          SVG
        end

        def background(left_width, right_width, width)
          <<~SVG
            <g clip-path="url(#r)">
              <rect width="#{left_width}" height="20" fill="#fff"/>
              <rect x="#{left_width}" width="#{right_width}" height="20" fill="#dc143c"/>
              <rect width="#{width}" height="20" fill="url(#s)"/>
            </g>
          SVG
        end

        def text(labels)
          left_width = labels.fetch(:left_width)
          right_width = labels.fetch(:right_width)
          <<~SVG
            <g font-family="Verdana,Geneva,DejaVu Sans,sans-serif" font-size="11" text-anchor="middle">
              <text x="#{left_width / 2}" y="14" fill="#222">#{Rack::Utils.escape_html(labels.fetch(:left))}</text>
              <text x="#{left_width + (right_width / 2)}" y="14" fill="#fff">#{Rack::Utils.escape_html(labels.fetch(:right))}</text>
            </g>
          SVG
        end
      end
    end
  end
end
