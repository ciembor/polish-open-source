# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Composition do
  it 'builds default Discord gateway and sync use case from configuration' do
    database_path = File.join(Dir.mktmpdir, 'rank.sqlite3')
    configuration = instance_double(
      PolishOpenSourceRank::Configuration,
      database_path: database_path,
      discord_bot_token: 'bot-token',
      discord_guild_id: 'guild-1',
      http_timeouts: { open_timeout: 1, read_timeout: 2, write_timeout: 3 }
    )

    composition = described_class.new(configuration: configuration)

    expect(composition.discord_gateway).to be_a(
      PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway
    )
    expect(composition.sync_discord_connection).to be_a(
      PolishOpenSourceRank::Contexts::Community::Application::SyncDiscordConnection
    )
  end
end
