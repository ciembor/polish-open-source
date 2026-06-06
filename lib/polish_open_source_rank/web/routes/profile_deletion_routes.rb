# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Routes
      module ProfileDeletionRoutes
        def self.registered(app)
          app.post('/users/:platform/:login/:name_slug/delete') do
            delete_user_profile(params.fetch('platform'), params.fetch('login'))
          end
          app.post('/users/:platform/:login/delete') do
            delete_user_profile(params.fetch('platform'), params.fetch('login'))
          end
        end
      end
    end
  end
end
