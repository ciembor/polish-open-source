# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Domain::BadgePolicy do
  it 'classifies user badges from current and historical ranks' do
    policy = described_class.new

    expect(policy.user_badges(2, historical_top_ten: false, historical_top_hundred: true)).to contain_exactly(
      include(label: 'Polish Elite', value: '2nd', status: 'ranked', rank: 2),
      include(label: 'Polish Top 100', value: '2nd', status: 'ranked', rank: 2)
    )
    expect(policy.user_badges(20, historical_top_ten: true, historical_top_hundred: true)).to contain_exactly(
      include(label: 'Polish Top 100', value: '20th', status: 'ranked', rank: 20)
    )
    expect(policy.user_badges(nil, historical_top_ten: true, historical_top_hundred: true)).to contain_exactly(
      include(label: 'Polish Elite', value: 'ex', status: 'ex'),
      include(label: 'Polish Top 100', value: 'ex', status: 'ex')
    )
    expect(policy.user_badge(20, historical_top_ten: false, historical_top_hundred: true)).to include(
      label: 'Polish Top 100', value: '20th', status: 'ranked'
    )
  end

  it 'classifies repository badges wherever they are ranked' do
    policy = described_class.new

    expect(policy.repository_badge(13)).to include(value: '13th', status: 'ranked', rank: 13)
    expect(policy.repository_badge(101)).to include(value: '101st', status: 'ranked', rank: 101)
  end
end
