# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    # Provides stable cache revision values for period-scoped public responses.
    class PublicCacheRevision
      def initialize(read_model:)
        @read_model = read_model
      end

      def for_period(period)
        read_model.public_cache_revision(period) || 'empty'
      end

      def latest_key(period)
        "#{period}:#{for_period(period)}"
      end

      private

      attr_reader :read_model
    end
  end
end
