# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      module InternalRoutes
        def self.registered(app)
          register_health_check(app)
          register_job_monitor(app)
          register_discord_invites(app)
        end

        class << self
          private

          def register_health_check(app)
            app.get('/healthz') do
              headers 'Cache-Control' => 'no-store'
              'ok'
            end
          end

          def register_job_monitor(app)
            app.get '/internal/jobs' do
              headers 'Cache-Control' => 'no-store', 'X-Robots-Tag' => 'noindex, nofollow, noarchive'
              @robots = 'noindex,nofollow,noarchive'
              @refresh_seconds = 15
              @progress = operations.show_job_progress.call
              @title = 'Job monitor'
              @description = 'Internal monthly ranking job monitor.'
              @canonical_path = '/internal/jobs'
              erb :'internal/job_monitor'
            end
          end

          def register_discord_invites(app)
            app.get '/internal/discord-invites' do
              headers 'Cache-Control' => 'no-store', 'X-Robots-Tag' => 'noindex, nofollow, noarchive'
              @robots = 'noindex,nofollow,noarchive'
              @title = 'Discord invites'
              @description = 'Internal manual Discord invites.'
              @canonical_path = '/internal/discord-invites'
              @invites = community.manual_discord_invite_repository.active_invites
              erb :'internal/discord_invites'
            end

            app.post '/internal/discord-invites' do
              headers 'Cache-Control' => 'no-store', 'X-Robots-Tag' => 'noindex, nofollow, noarchive'
              halt 403 unless valid_csrf_token?

              result = community.invite_discord_guest.call(
                login: params.fetch('login', ''),
                invited_by: internal_actor
              )
              session[:manual_discord_invite_url] = result.invite.fetch(:url)
              redirect app_path('/internal/discord-invites')
            end
          end
        end
      end
    end
  end
end
