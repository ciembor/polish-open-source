# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordRoleMap do
  around do |example|
    previous = ENV.to_h
    ENV.delete_if { |key, _| key.start_with?('DISCORD_ROLE_') }
    example.run
  ensure
    ENV.replace(previous)
  end

  it 'maps configured role keys to Discord role ids' do
    ENV['DISCORD_ROLE_TOP_100_PL'] = '100'
    ENV['DISCORD_ROLE_TOP_100_CITY_KRAKOW'] = 'krk'

    map = described_class.new
    prepared = map.prepare(period_start: '2026-04-01')

    expect(prepared.role_ids(%w[DISCORD_ROLE_TOP_100_PL])).to eq(['100'])
    expect(map.managed_role_ids).to include('100', 'krk')
  end

  context 'with published languages' do
    let(:initial_channels) { [] }
    let(:gateway_data) do
      { roles: [], channels: initial_channels.map(&:dup), created_roles: [], created_channels: [] }
    end
    let(:gateway) do
      roles, channels, created_roles, created_channels =
        gateway_data.values_at(:roles, :channels, :created_roles, :created_channels)

      double('DiscordGateway').tap do |stub|
        allow(stub).to receive_messages(guild_roles: roles, guild_channels: channels)
        allow(stub).to receive(:private_channel_overwrites) { |role_id| [{ id: role_id }] }
        allow(stub).to receive(:create_role) do |name:, color: nil|
          role = { 'id' => "role-#{created_roles.size + 1}", 'name' => name, 'color' => color }
          roles << role
          created_roles << role
          role
        end
        allow(stub).to receive(:create_channel) do |name:, type:, parent_id: nil, permission_overwrites: nil|
          channel = {
            'id' => "channel-#{created_channels.size + 1}",
            'name' => name,
            'type' => type,
            'parent_id' => parent_id,
            'permission_overwrites' => permission_overwrites || []
          }
          channels << channel
          created_channels << channel
          channel
        end
      end
    end
    let(:published_language_source) do
      double('PublishedLanguageSource').tap do |source|
        allow(source).to receive(:published_languages)
          .with(period_start: '2026-04-01')
          .and_return(['Ruby'])
      end
    end
    let(:map) do
      described_class.new(
        gateway: gateway,
        published_language_source: published_language_source
      )
    end

    it 'provisions dynamic language roles and channels from published languages' do
      prepared = map.prepare(period_start: '2026-04-01')

      expect(prepared.role_ids_by_key).to include(
        'DISCORD_ROLE_LANGUAGE:ruby:Ruby' => 'role-1',
        'DISCORD_ROLE_TOP_100_LANGUAGE:ruby:Ruby' => 'role-2'
      )
      expect(prepared.managed_role_ids).to include('role-1', 'role-2')
      expect(gateway_data.fetch(:created_roles).map { |role| role.fetch('name') }).to eq(['Ruby', 'Top 100 Ruby'])
      expect(gateway_data.fetch(:created_channels).map do |channel|
        channel.fetch('name')
      end).to eq(%w[Languages ruby top-100-ruby])
    end

    context 'when the Languages category already exists' do
      let(:initial_channels) do
        [{ 'id' => 'category-1', 'name' => 'Languages', 'type' => 4, 'permission_overwrites' => [] }]
      end

      it 'reuses the category for language channels' do
        map.prepare(period_start: '2026-04-01')

        expect(gateway_data.fetch(:created_channels).map { |channel| channel.fetch('name') })
          .to eq(%w[ruby top-100-ruby])
        expect(gateway_data.fetch(:created_channels).map { |channel| channel.fetch('parent_id') })
          .to all(eq('category-1'))
      end
    end
  end
end
