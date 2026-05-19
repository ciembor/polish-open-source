# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Infrastructure::DiscordInviteBot do
  it 'builds production collaborators from configuration' do
    discord_bot = FakeDiscordBot.new
    configuration = instance_double(
      PolishOpenSourceRank::Configuration,
      discord_guild_id: '1505949566229286972',
      discord_bot_token: 'token'
    )
    allow(Discordrb::Bot).to receive(:new)
      .with(token: 'token', intents: %i[server_invites])
      .and_return(discord_bot)

    bot = described_class.build(
      configuration: configuration,
      store: instance_double(PolishOpenSourceRank::Infrastructure::SQLiteStore)
    )

    expect(bot).to be_a(described_class)
  end

  it 'syncs a joined Discord member through the invite that changed', :aggregate_failures do
    discord_bot = FakeDiscordBot.new
    join_handler = JoinHandlerSpy.new
    logger = StringIO.new
    discord_bot.server.invite_sets = [
      [invite('for-alice', 0)],
      [],
      []
    ]
    bot = described_class.new(
      guild_id: '1505949566229286972',
      logger: logger,
      bot: discord_bot,
      join_handler: join_handler
    )

    bot.run
    discord_bot.trigger(:ready)
    discord_bot.trigger(:member_join, event('discord-1', 'Alice Discord'))

    expect(join_handler.calls).to contain_exactly(
      invite_code: 'for-alice',
      discord_user_id: 'discord-1',
      discord_username: 'Alice Discord'
    )
    expect(logger.string).to include('discord invite for-alice synced for discord-1: true')
  end

  it 'skips joined members when the invite use is ambiguous' do
    discord_bot = FakeDiscordBot.new
    join_handler = JoinHandlerSpy.new
    logger = StringIO.new
    discord_bot.server.invite_sets = [
      [invite('a', 0), invite('b', 0)],
      [],
      []
    ]
    bot = described_class.new(
      guild_id: '1505949566229286972',
      logger: logger,
      bot: discord_bot,
      join_handler: join_handler
    )

    bot.run
    discord_bot.trigger(:ready)
    discord_bot.trigger(:member_join, event('discord-1', 'Alice Discord'))

    expect(join_handler.calls).to be_empty
    expect(logger.string).to include('invite code ambiguous')
  end

  it 'logs invite refresh and join sync failures' do
    discord_bot = FakeDiscordBot.new
    logger = StringIO.new
    discord_bot.server.invite_sets = [
      StandardError.new('invite api failed'),
      [invite('for-alice', 0)],
      []
    ]
    bot = described_class.new(
      guild_id: '1505949566229286972',
      logger: logger,
      bot: discord_bot,
      join_handler: FailingJoinHandler.new
    )

    bot.run
    discord_bot.trigger(:ready)
    discord_bot.trigger(:invite_create)
    discord_bot.trigger(:member_join, event('discord-1', 'Alice Discord'))

    expect(logger.string).to include('discord invite cache refresh failed: StandardError: invite api failed')
    expect(logger.string).to include('discord invite join failed for discord-1: RuntimeError: sync failed')
  end

  # rubocop:disable Lint/ConstantDefinitionInBlock
  def invite(code, uses)
    instance_double(Discordrb::Invite, code: code, uses: uses)
  end

  def event(user_id, username)
    user = instance_double(Discordrb::User, id: user_id, global_name: username, username: username)
    instance_double(Discordrb::Events::ServerMemberAddEvent, user: user)
  end

  class FakeDiscordBot
    def initialize
      @handlers = {}
      @server = FakeDiscordServer.new
    end

    def server(_id = nil)
      @server
    end

    def ready(&block)
      @handlers[:ready] = block
    end

    def invite_create(&block)
      @handlers[:invite_create] = block
    end

    def invite_delete(&block)
      @handlers[:invite_delete] = block
    end

    def member_join(&block)
      @handlers[:member_join] = block
    end

    def run; end

    def trigger(name, event = nil)
      @handlers.fetch(name).call(event)
    end
  end

  class FakeDiscordServer
    attr_writer :invite_sets

    def invites
      invite_set = @invite_sets.shift
      raise invite_set if invite_set.is_a?(StandardError)

      invite_set
    end
  end

  class JoinHandlerSpy
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(**attributes)
      calls << attributes
      true
    end
  end

  class FailingJoinHandler
    def call(**_attributes)
      raise 'sync failed'
    end
  end
  # rubocop:enable Lint/ConstantDefinitionInBlock
end
