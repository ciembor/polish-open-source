# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Domain
        # Parses dynamic Discord language role keys and exposes their derived names.
        class DiscordLanguageRoleKey
          TOP_PREFIX = 'DISCORD_ROLE_TOP_100_LANGUAGE'
          OPEN_PREFIX = 'DISCORD_ROLE_LANGUAGE'
          TOP_COLOR = 0x3498DB

          def initialize(role_key)
            @role_key = role_key
          end

          def dynamic?
            !!parsed
          end

          def role_name
            parsed&.fetch(:role_name)
          end

          def role_color
            parsed&.fetch(:role_color)
          end

          def channel_name
            parsed&.fetch(:channel_name)
          end

          def self.build_top(language)
            build(TOP_PREFIX, language)
          end

          def self.build_open(language)
            build(OPEN_PREFIX, language)
          end

          private

          attr_reader :role_key

          def self.build(prefix, language)
            "#{prefix}:#{language_slug(language)}:#{language}"
          end

          def self.language_slug(language)
            language.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
          end
          private_class_method :build, :language_slug

          def parsed
            @parsed ||= begin
              prefix, slug, language = role_key.split(':', 3)
              case prefix
              when TOP_PREFIX
                { role_name: "Top 100 #{language}", role_color: TOP_COLOR, channel_name: "top-100-#{slug}" }
              when OPEN_PREFIX
                { role_name: language, role_color: nil, channel_name: slug }
              end
            end
          end
        end
      end
    end
  end
end
