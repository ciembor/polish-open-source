# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Domain::RepositoryMetrics do
  it 'accumulates repository counts and star totals' do
    metrics = described_class.empty

    metrics.add(source_repository(12), 3)
    metrics.add(source_repository(5), 2)

    expect(metrics).to have_attributes(
      public_repository_count: 2,
      total_stars: 17,
      monthly_stars_delta: 5
    )
  end

  def source_repository(stars)
    PolishOpenSourceRank::Contexts::Ranking::Domain::SourceRepository.new(
      source_id: stars,
      name: "repo-#{stars}",
      full_name: "alice/repo-#{stars}",
      html_url: "https://github.com/alice/repo-#{stars}",
      fork: false,
      archived: false,
      stars: stars
    )
  end
end
