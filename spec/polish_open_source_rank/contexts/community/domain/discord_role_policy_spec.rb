# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Community::Domain::DiscordRolePolicy do
  it 'derives Discord access and badge role keys from ranks' do
    policy = described_class.new

    expect(
      policy.role_keys(
        country_rank: 8,
        city_slug: 'krakow',
        city_rank: 99,
        language_accesses: [
          { language: 'Ruby', member: true, rank: 3 },
          { language: 'Elixir', member: true, rank: nil }
        ]
      )
    ).to eq(
      [
        'DISCORD_ROLE_TOP_100_PL',
        'DISCORD_ROLE_TOP_100_CITY_KRAKOW',
        'DISCORD_ROLE_LANGUAGE:ruby:Ruby',
        'DISCORD_ROLE_TOP_100_LANGUAGE:ruby:Ruby',
        'DISCORD_ROLE_LANGUAGE:elixir:Elixir'
      ]
    )
    expect(
      policy.role_keys(
        country_rank: 80,
        city_slug: 'gorzow-wielkopolski',
        city_rank: 101,
        language_accesses: []
      )
    ).to eq(
      %w[DISCORD_ROLE_TOP_100_PL]
    )
    expect([1, 2, 3, 4].map { |rank| policy.badge_role_key(rank) }).to eq(
      ['DISCORD_ROLE_BADGE_TOP_1', 'DISCORD_ROLE_BADGE_TOP_2', 'DISCORD_ROLE_BADGE_TOP_3', nil]
    )
  end

  it 'exposes dynamic language role helpers through the catalog' do
    role_key = PolishOpenSourceRank::Contexts::Community::Domain::DiscordLanguageRoleKey.new(
      'DISCORD_ROLE_LANGUAGE:ruby:Ruby'
    )

    expect(role_key.dynamic?).to be(true)
    expect(
      PolishOpenSourceRank::Contexts::Community::Domain::DiscordLanguageRoleKey.new('DISCORD_ROLE_TOP_100_PL').dynamic?
    ).to be(false)
  end
end
