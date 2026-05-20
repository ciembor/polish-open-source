# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Community::Domain::DiscordRolePolicy do
  it 'derives Discord access and badge role keys from ranks' do
    policy = described_class.new

    expect(policy.role_keys(country_rank: 8, city_slug: 'krakow', city_rank: 99)).to eq(
      %w[DISCORD_ROLE_TOP_10_PL DISCORD_ROLE_TOP_100_PL DISCORD_ROLE_TOP_100_CITY_KRAKOW]
    )
    expect(policy.role_keys(country_rank: 80, city_slug: 'gorzow-wielkopolski', city_rank: 101)).to eq(
      %w[DISCORD_ROLE_TOP_100_PL]
    )
    expect([1, 2, 3, 4].map { |rank| policy.badge_role_key(rank) }).to eq(
      ['DISCORD_ROLE_BADGE_TOP_1', 'DISCORD_ROLE_BADGE_TOP_2', 'DISCORD_ROLE_BADGE_TOP_3', nil]
    )
  end
end
