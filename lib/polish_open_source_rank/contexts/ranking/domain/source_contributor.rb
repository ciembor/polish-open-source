# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        class SourceContributor
          include SourceRecord

          attr_reader :avatar_url, :email, :homepage, :html_url, :location, :login, :name, :source_id

          def initialize(source_id:, login:, html_url:, **attributes)
            @source_id = required_source_id(source_id)
            @login = Shared::Domain::Login.new(login).to_s
            @html_url = required_string(html_url, 'html_url')
            @name = optional_string(attributes[:name])
            @location = optional_string(attributes[:location])
            @email = optional_string(attributes[:email])
            @homepage = optional_string(attributes[:homepage])
            @avatar_url = optional_string(attributes[:avatar_url])
            freeze
          end

          def location_evidence
            location
          end

          def to_h
            {
              source_id: source_id,
              login: login,
              name: name,
              location: location,
              email: email,
              homepage: homepage,
              html_url: html_url,
              avatar_url: avatar_url
            }
          end
        end
      end
    end
  end
end
