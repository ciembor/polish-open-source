# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Domain::RankingMetric do
  it 'owns supported ranking metric columns' do
    expect(described_class.column(:user_top)).to eq('total_stars')
    expect(described_class.column(:repository_trending)).to eq('monthly_stars_delta')
    expect(described_class).to be_trending('monthly_stars_delta')
    expect(described_class).not_to be_trending('total_stars')
  end
end
