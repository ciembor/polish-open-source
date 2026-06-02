# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        class SourceRepository
          include SourceRecord

          attr_reader :archived, :description, :fork, :full_name, :homepage, :html_url, :language, :name, :source_id,
                      :stars

          def initialize(source_id:, name:, full_name:, html_url:, stars:, **attributes)
            @source_id = required_source_id(source_id)
            @full_name = required_string(full_name, 'full_name')
            @name = required_string(name, 'name')
            @html_url = required_string(html_url, 'html_url')
            @description = optional_string(attributes[:description])
            @homepage = optional_string(attributes[:homepage])
            @language = optional_string(attributes[:language])
            @fork = explicitly_true?(attributes.fetch(:fork))
            @archived = explicitly_true?(attributes.fetch(:archived))
            @stars = Integer(stars)
            raise ArgumentError, 'stars cannot be negative' if @stars.negative?

            freeze
          end

          def with_stars(value)
            self.class.new(**to_h, stars: value)
          end

          def zero_stars?
            stars.zero?
          end

          def at_least_stars?(minimum)
            stars >= minimum
          end

          def to_h
            {
              source_id: source_id,
              name: name,
              full_name: full_name,
              description: description,
              html_url: html_url,
              homepage: homepage,
              language: language,
              fork: fork,
              archived: archived,
              stars: stars
            }
          end
        end
      end
    end
  end
end
