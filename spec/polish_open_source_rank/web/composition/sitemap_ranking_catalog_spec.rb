# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Composition::SitemapRankingCatalog do
  subject(:paths) { catalog.paths(latest_period: '2026-04-01', period_slugs: []) }

  let(:package_ranking_read_model) do
    instance_double(
      PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageRankingReadModel,
      ecosystems: ['npm']
    )
  end
  let(:catalog) do
    described_class.new(
      catalogs: [
        PolishOpenSourceRank::Web::Composition::PublicRankingSitemapCatalog.new,
        PolishOpenSourceRank::Web::Composition::LanguageRankingSitemapCatalog.new,
        PolishOpenSourceRank::Web::Composition::PackageRankingSitemapCatalog.new(
          package_ranking_read_model: package_ranking_read_model
        )
      ]
    )
  end

  before do
    allow(PolishOpenSourceRank::Contexts::Ranking::Domain::LocationCatalog).to receive(:city_slugs).and_return([])
  end

  it 'adds canonical ranking pages without probing paginated result sets', :aggregate_failures do
    expect(paths).to include(
      '/people/users/top',
      '/languages/top',
      '/packages/npm/top'
    )
    expect(paths).not_to include(
      '/people/users/top/page/2',
      '/people/users/top/page/3',
      '/languages/top/page/2',
      '/languages/top/page/3',
      '/packages/npm/top/page/2',
      '/packages/npm/top/page/3'
    )
  end
end
