# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        class SourceCandidate
          include SourceRecord

          attr_reader :login, :platform, :source_id

          def initialize(source_id:, login:, platform: nil)
            @source_id = required_source_id(source_id)
            @login = Shared::Domain::Login.new(login).to_s
            @platform = platform && Shared::Domain::Platform.coerce(platform).to_s
            freeze
          end

          def identity
            raise ArgumentError, 'platform is required for source identity' unless platform

            Shared::Domain::SourceIdentity.new(platform: platform, source_id: source_id)
          end

          def to_h
            attributes = { source_id: source_id, login: login }
            platform ? attributes.merge(platform: platform) : attributes
          end
        end
      end
    end
  end
end
