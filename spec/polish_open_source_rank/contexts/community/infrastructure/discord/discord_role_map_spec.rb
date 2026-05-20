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
    ENV['DISCORD_ROLE_TOP_10_PL'] = '10'
    ENV['DISCORD_ROLE_TOP_100_CITY_KRAKOW'] = 'krk'

    map = described_class.new

    expect(map.role_ids(%w[DISCORD_ROLE_TOP_10_PL DISCORD_ROLE_TOP_100_PL])).to eq(['10'])
    expect(map.managed_role_ids).to include('10', 'krk')
  end
end
