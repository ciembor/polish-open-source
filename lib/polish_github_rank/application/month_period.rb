# frozen_string_literal: true

module PolishGithubRank
  module Application
    MonthPeriod = Struct.new(:start_date, :end_date, keyword_init: true) do
      def self.previous_month(today = Date.today)
        first_day = Date.new(today.year, today.month, 1)
        from_month(first_day << 1)
      end

      def self.parse(value)
        year, month = value.split('-', 2).map(&:to_i)
        from_month(Date.new(year, month, 1))
      end

      def self.from_month(date)
        start_date = Date.new(date.year, date.month, 1)
        end_date = start_date.next_month
        new(start_date: start_date, end_date: end_date)
      end

      def key
        start_date.strftime('%Y-%m')
      end

      def cover_time?(time)
        date = time.to_date
        date >= start_date && date < end_date
      end
    end
  end
end
