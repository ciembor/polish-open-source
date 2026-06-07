# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      class RankingPaginator
        PER_PAGE = 100
        QUERY_LIMIT = PER_PAGE + 1
        MAX_PAGE = 10_000
        class InvalidPage < StandardError; end

        Page = Data.define(:records, :number, :offset, :previous_page, :next_page)

        attr_reader :number

        def initialize(raw_page)
          @number = parse_page(raw_page)
        end

        def fetch
          records = yield(limit: QUERY_LIMIT, offset: offset)
          raise InvalidPage if number > 1 && records.empty?

          Page.new(
            records: records.first(PER_PAGE),
            number: number,
            offset: offset,
            previous_page: number > 1 ? number - 1 : nil,
            next_page: records.length > PER_PAGE ? number + 1 : nil
          )
        end

        private

        def offset
          (number - 1) * PER_PAGE
        end

        def parse_page(raw_page)
          return 1 if raw_page.nil? || raw_page.empty?
          raise InvalidPage unless raw_page.match?(/\A[1-9]\d*\z/)

          raw_page.to_i.tap { |page| raise InvalidPage if page > MAX_PAGE }
        end
      end
    end
  end
end
