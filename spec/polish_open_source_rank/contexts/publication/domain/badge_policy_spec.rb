# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Domain::BadgePolicy do
  it 'classifies user badges from country and city ranks' do
    policy = described_class.new

    expect(
      policy.user_badges(
        profile: { country_rank: 2, city: 'Krakow', city_rank: 2 },
        language_badge: { label: 'Polish RB Top 100', value: '4th', status: 'ranked', rank: 4 }
      )
    ).to match(
      [
        include(label: 'Polish Open Source', value: '2nd', status: 'ranked', rank: 2),
        include(label: 'Polish RB Top 100', value: '4th', status: 'ranked', rank: 4),
        include(label: 'Krakow Elite', value: '2nd', status: 'ranked', rank: 2)
      ]
    )
    expect(policy.user_badges(profile: { country_rank: nil, city: 'Krakow', city_rank: 8 },
                              language_badge: nil)).to contain_exactly(
                                include(label: 'Krakow Elite', value: '8th',
                                        status: 'ranked', rank: 8)
                              )
    expect(policy.user_badges(profile: { country_rank: nil, city: 'Krakow', city_rank: 20 },
                              language_badge: nil)).to contain_exactly(
                                include(label: 'Krakow Top 100', value: '20th',
                                        status: 'ranked', rank: 20)
                              )
    expect(policy.user_badge(profile: { country_rank: nil, city: nil, city_rank: nil },
                             language_badge: nil)).to include(
                               label: 'Polish Open Source', value: nil, status: 'outside_ranking'
                             )
  end

  it 'classifies repository badges wherever they are ranked' do
    policy = described_class.new

    expect(policy.repository_badge(13)).to include(value: '13th', status: 'ranked', rank: 13)
    expect(policy.repository_badge(101)).to include(value: '101st', status: 'ranked', rank: 101)
  end

  it 'classifies organization badges and organization repository badges' do
    policy = described_class.new

    expect(policy.organization_badge(3)).to include(label: 'Polish Open Source Org', value: '3rd', rank: 3)
    expect(policy.organization_badge(nil)).to include(label: 'Polish Open Source Org', value: nil)
    expect(policy.organization_repository_badge(8)).to include(label: 'Polish Org Repo', value: '8th', rank: 8)
    expect(policy.organization_repository_badge(nil)).to include(label: 'Polish Org Repo', value: nil)
  end

  it 'builds fallback codes for unknown language badge labels' do
    expect(PolishOpenSourceRank::Contexts::Publication::Domain::LanguageBadgeLabel.code('Nim Lang')).to eq('NIMLANG')
  end
end
