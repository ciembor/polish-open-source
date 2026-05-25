# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      module InternalRoutes
        def self.registered(app)
          app.get('/healthz') do
            headers 'Cache-Control' => 'no-store'
            'ok'
          end

          app.get '/internal/jobs' do
            headers 'Cache-Control' => 'no-store', 'X-Robots-Tag' => 'noindex'
            @robots = 'noindex,nofollow'
            @refresh_seconds = 15
            @progress = show_job_progress.call
            @title = 'Job monitor'
            @description = 'Internal monthly ranking job monitor.'
            @canonical_path = '/internal/jobs'
            erb :'internal/job_monitor'
          end
        end
      end
    end
  end
end
