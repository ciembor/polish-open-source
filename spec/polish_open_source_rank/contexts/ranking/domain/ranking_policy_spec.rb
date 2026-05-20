# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Domain::RankingPolicy do
  it 'owns ranking metrics, limits, tie breakers, and trending semantics' do
    expect(described_class::USER_RANKINGS.fetch(:top).column).to eq('total_stars')
    expect(described_class::USER_RANKINGS.fetch(:active).column).to eq('public_activity_count')
    expect(described_class::REPOSITORY_RANKINGS.fetch(:top).column).to eq('stargazers_count')
    expect(described_class.metric(:repository_trending)).to be_trending
    expect(described_class).to be_trending('monthly_stars_delta')
    expect(described_class.bounded_limit('1000; DROP TABLE users')).to eq(100)
    expect(described_class.bounded_limit(0)).to eq(1)
    expect(described_class::USER_TIE_BREAKER).to eq('login COLLATE NOCASE ASC')
    expect(described_class::REPOSITORY_TIE_BREAKER).to include('repository_github_id ASC')
  end
end
