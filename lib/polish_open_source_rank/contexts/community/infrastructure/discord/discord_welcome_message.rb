# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Infrastructure
        module Discord
          class DiscordWelcomeMessage
            MAX_FIELD_LENGTH = 1024
            MAX_PROJECTS = 5

            def initialize(discord_user_id:, profile:, access:, role_names:, writable_channels:)
              @discord_user_id = discord_user_id
              @profile = profile
              @access = access
              @role_names = role_names
              @writable_channels = writable_channels
            end

            def payload
              {
                content: "Witaj <@#{discord_user_id}> - profil GitHub: #{profile.fetch(:html_url)}",
                allowed_mentions: { users: [discord_user_id] },
                embeds: [embed]
              }
            end

            private

            attr_reader :discord_user_id, :profile, :access, :role_names, :writable_channels

            def embed
              {
                title: display_name,
                url: profile.fetch(:html_url),
                description: 'Nowy czlonek z rankingu Polish Open Source.',
                color: embed_color,
                thumbnail: thumbnail,
                fields: fields,
                footer: { text: 'Polish Open Source' }
              }.compact
            end

            def display_name
              name = profile[:name].to_s.strip
              name.empty? ? profile.fetch(:login) : "#{name} (@#{profile.fetch(:login)})"
            end

            def thumbnail
              avatar_url = profile[:avatar_url].to_s.strip
              return if avatar_url.empty?

              { url: avatar_url }
            end

            def fields
              [
                field('GitHub', "[#{profile.fetch(:login)}](#{profile.fetch(:html_url)})"),
                optional_field('Website', profile[:homepage]),
                field('Ranking', ranking_lines.join("\n")),
                field('Role', role_lines.join("\n")),
                field('Kanaly do pisania', channel_lines.join("\n")),
                optional_field('Najlepsze projekty', project_lines.join("\n"))
              ].compact
            end

            def field(name, value)
              { name: name, value: truncate_field(value) }
            end

            def optional_field(name, value)
              value = value.to_s.strip
              return if value.empty?

              field(name, value)
            end

            def ranking_lines
              lines = [
                access[:country_rank] && "Polska: ##{access.fetch(:country_rank)}",
                access[:city] && access[:city_rank] && "#{access.fetch(:city)}: ##{access.fetch(:city_rank)}"
              ].compact
              lines.empty? ? ['brak pozycji'] : lines
            end

            def role_lines
              return ['brak rol rankingowych'] if role_names.empty?

              role_names.map { |name| "- #{name}" }
            end

            def channel_lines
              return ['brak wykrytych kanalow'] if writable_channels.empty?

              writable_channels.map { |channel| "- #{channel}" }
            end

            def project_lines
              repositories = profile.fetch(:repositories, []).first(MAX_PROJECTS)
              return [] if repositories.empty?

              repositories.map do |repository|
                stars = repository.fetch(:stargazers_count).to_i
                "- [#{repository.fetch(:full_name)}](#{repository.fetch(:html_url)}) - #{format_number(stars)} stars"
              end
            end

            def embed_color
              country_rank = access[:country_rank]
              return 0xE74C3C if country_rank && country_rank <= 10
              return 0x3498DB if country_rank && country_rank <= 100

              0
            end

            def truncate_field(value)
              value.length > MAX_FIELD_LENGTH ? "#{value[0, MAX_FIELD_LENGTH - 1]}..." : value
            end

            def format_number(value)
              value.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1 ').reverse
            end
          end
        end
      end
    end
  end
end
