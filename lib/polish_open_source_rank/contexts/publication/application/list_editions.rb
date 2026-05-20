# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class ListEditions
          EditionIndex = Struct.new(:years, :year, :editions, :newer_year, :older_year, keyword_init: true)

          def initialize(edition_read_model:)
            @edition_read_model = edition_read_model
          end

          def call(year: nil, scope: 'poland')
            years = edition_read_model.edition_years.map { |row| row.fetch(:year) }
            selected_year = year || years.first
            return if year && !years.include?(year)

            EditionIndex.new(
              years: years,
              year: selected_year,
              editions: selected_year ? edition_read_model.monthly_editions(selected_year, scope: scope) : [],
              newer_year: adjacent_year(years, selected_year, -1),
              older_year: adjacent_year(years, selected_year, 1)
            )
          end

          private

          attr_reader :edition_read_model

          def adjacent_year(years, year, offset)
            index = years.index(year)
            return unless index

            years[index + offset] unless (index + offset).negative?
          end
        end
      end
    end
  end
end
