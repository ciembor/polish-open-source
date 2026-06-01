# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module AuthController
        private

        def auth_path?
          request.path_info.start_with?('/auth/') || request.path_info == '/auth/github' ||
            request.path_info == '/auth/discord' || request.path_info == '/logout'
        end

        def discord_channel_url
          guild_id = ENV.fetch('DISCORD_GUILD_ID', '').strip
          channel_id = ENV.fetch('DISCORD_INVITE_CHANNEL_ID', '').strip
          return if guild_id.empty? || channel_id.empty?

          "https://discord.com/channels/#{guild_id}/#{channel_id}"
        end

        def discord_welcome_channel_id
          ENV.fetch('DISCORD_WELCOME_CHANNEL_ID', configuration.discord_invite_channel_id)
        end

        def redirect_to_profile_after_discord_error(type)
          session[:discord_error] = type
          redirect app_path(user_profile_path(current_user))
        end

        def csrf_token
          session[:csrf_token] ||= SecureRandom.hex(32)
        end

        def valid_csrf_token?
          expected = session[:csrf_token]
          given = params.fetch('csrf_token', nil)
          expected && given && expected.bytesize == given.bytesize && Rack::Utils.secure_compare(expected, given)
        end

        def secure_oauth_state?(session_key)
          expected = session.delete(session_key)
          given = params.fetch('state', nil)
          expected && given && expected.bytesize == given.bytesize && Rack::Utils.secure_compare(expected, given)
        end

        def oauth_callback_url(path)
          "#{configuration.public_base_url.delete_suffix('/')}#{path}"
        end
      end
    end
  end
end
