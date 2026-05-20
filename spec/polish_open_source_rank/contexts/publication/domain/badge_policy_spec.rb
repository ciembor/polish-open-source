# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Domain::BadgePolicy do
  it 'classifies user badges from current and historical ranks' do
    policy = described_class.new

    expect(policy.user_badge(2, historical_top_ten: false)).to include(value: '2nd', status: 'ranked', rank: 2)
    expect(policy.user_badge(20, historical_top_ten: true)).to include(value: 'alumni', status: 'alumni')
    expect(policy.user_badge(nil, historical_top_ten: false)).to include(value: 'contender', status: 'contender')
  end

  it 'classifies repository badges inside and outside top 100' do
    policy = described_class.new

    expect(policy.repository_badge(13)).to include(value: '13th', status: 'ranked', rank: 13)
    expect(policy.repository_badge(101)).to include(value: nil, status: 'outside_top_100', rank: 101)
  end
end
