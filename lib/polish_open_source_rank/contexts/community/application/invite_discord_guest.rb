# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Community
      module Application
        class InviteDiscordGuest
          Result = Struct.new(:profile, :invite, keyword_init: true)

          def initialize(profile_source:, invite_gateway:, invite_repository:, invite_channel_id:)
            @profile_source = profile_source
            @invite_gateway = invite_gateway
            @invite_repository = invite_repository
            @invite_channel_id = invite_channel_id
          end

          def call(login:, invited_by:)
            profile = profile_source.user(login).to_h.merge(platform: profile_source.platform)
            invite = invite_gateway.create_invite(channel_id: invite_channel_id)
            invite_repository.record(profile: profile, invite: invite, invited_by: invited_by)
            Result.new(profile: profile, invite: invite)
          end

          private

          attr_reader :invite_channel_id, :invite_gateway, :invite_repository, :profile_source
        end
      end
    end
  end
end
