# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Domain::RepositoryMetrics do
  it 'accumulates repository counts and star totals' do
    metrics = described_class.empty

    metrics.add({ stars: 12 }, 3)
    metrics.add({ stars: 5 }, 2)

    expect(metrics).to have_attributes(
      public_repository_count: 2,
      total_stars: 17,
      monthly_stars_delta: 5
    )
  end
end
