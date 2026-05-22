# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Domain::BadgePolicy do
  it 'classifies user badges from country and city ranks' do
    policy = described_class.new

    expect(policy.user_badges(country_rank: 2, city: 'Krakow', city_rank: 2)).to contain_exactly(
      include(label: 'Polish Open Source', value: '2nd', status: 'ranked', rank: 2)
    )
    expect(policy.user_badges(country_rank: nil, city: 'Krakow', city_rank: 8)).to contain_exactly(
      include(label: 'Krakow Elite', value: '8th', status: 'ranked', rank: 8)
    )
    expect(policy.user_badges(country_rank: nil, city: 'Krakow', city_rank: 20)).to contain_exactly(
      include(label: 'Krakow Top 100', value: '20th', status: 'ranked', rank: 20)
    )
    expect(policy.user_badge(country_rank: nil, city: nil, city_rank: nil)).to include(
      label: 'Polish Open Source', value: nil, status: 'outside_ranking'
    )
  end

  it 'classifies repository badges wherever they are ranked' do
    policy = described_class.new

    expect(policy.repository_badge(13)).to include(value: '13th', status: 'ranked', rank: 13)
    expect(policy.repository_badge(101)).to include(value: '101st', status: 'ranked', rank: 101)
  end
end
