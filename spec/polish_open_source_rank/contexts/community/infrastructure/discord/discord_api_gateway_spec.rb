# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway do
  let(:configuration) do
    Struct.new(:discord_guild_id, :discord_bot_token).new('guild-1', 'bot-token')
  end

  it 'creates roles with optional colors' do
    gateway = described_class.new(configuration)
    requests = []
    allow(gateway).to receive(:json_request) do |uri, request|
      requests << [uri.to_s, request.method, JSON.parse(request.body)]
      {}
    end

    gateway.create_role(name: 'Ruby')
    gateway.create_role(name: 'Top 100 Ruby', color: 12_345)

    expect(requests).to eq([
                             ['https://discord.com/api/v10/guilds/guild-1/roles', 'POST', { 'name' => 'Ruby' }],
                             ['https://discord.com/api/v10/guilds/guild-1/roles', 'POST',
                              { 'name' => 'Top 100 Ruby', 'color' => 12_345 }]
                           ])
  end

  it 'creates channels with optional parent and overwrites' do
    gateway = described_class.new(configuration)
    requests = []
    allow(gateway).to receive(:json_request) do |uri, request|
      requests << [uri.to_s, request.method, JSON.parse(request.body)]
      {}
    end

    gateway.create_channel(name: 'ruby', type: 0)
    gateway.create_channel(
      name: 'top-100-ruby',
      type: 0,
      parent_id: 'category-1',
      permission_overwrites: [{ id: 'role-1' }]
    )

    expect(requests).to eq([
                             ['https://discord.com/api/v10/guilds/guild-1/channels', 'POST',
                              { 'name' => 'ruby', 'type' => 0 }],
                             [
                               'https://discord.com/api/v10/guilds/guild-1/channels',
                               'POST',
                               { 'name' => 'top-100-ruby', 'type' => 0, 'parent_id' => 'category-1',
                                 'permission_overwrites' => [{ 'id' => 'role-1' }] }
                             ]
                           ])
  end

  it 'builds private channel overwrites for the guild and allowed role' do
    gateway = described_class.new(configuration)

    expect(gateway.private_channel_overwrites('role-1')).to eq([
                                                                 { id: 'guild-1', type: 0, allow: '0', deny: '3072' },
                                                                 { id: 'role-1', type: 0, allow: '3072', deny: '0' }
                                                               ])
  end
end
