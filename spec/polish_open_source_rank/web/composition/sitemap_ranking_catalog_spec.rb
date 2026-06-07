# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Composition::SitemapRankingCatalog do
  subject(:paths) { catalog.paths(latest_period: '2026-04-01', period_slugs: []) }

  let(:package_ranking_read_model) do
    instance_double(
      PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageRankingReadModel,
      ecosystems: ['npm']
    )
  end
  let(:show_ranking_detail) do
    lambda do |scope:, kind:, metric:, offset:, **|
      next [] unless scope == 'poland' && kind == 'users' && metric == 'top'

      offset <= 200 ? [{ login: 'alice' }] : []
    end
  end
  let(:show_language_ranking_detail) do
    lambda do |metric:, offset:, **|
      metric == 'repository_count' && offset == 100 ? [{ language: 'Ruby' }] : []
    end
  end
  let(:show_package_ranking_detail) do
    lambda do |ecosystem:, metric:, offset:, **|
      ecosystem == 'npm' && metric == 'downloads_30d' && offset == 100 ? [{ package_name: 'rack' }] : []
    end
  end
  let(:catalog) do
    described_class.new(
      catalogs: [
        PolishOpenSourceRank::Web::Composition::PublicRankingSitemapCatalog.new(
          show_ranking_detail: show_ranking_detail
        ),
        PolishOpenSourceRank::Web::Composition::LanguageRankingSitemapCatalog.new(
          show_language_ranking_detail: show_language_ranking_detail
        ),
        PolishOpenSourceRank::Web::Composition::PackageRankingSitemapCatalog.new(
          package_ranking_read_model: package_ranking_read_model,
          show_package_ranking_detail: show_package_ranking_detail
        )
      ]
    )
  end

  before do
    allow(PolishOpenSourceRank::Contexts::Ranking::Domain::LocationCatalog).to receive(:city_slugs).and_return([])
  end

  it 'adds every non-empty ranking page and stops at the first empty page', :aggregate_failures do
    expect(paths).to include(
      '/people/users/top',
      '/people/users/top/page/2',
      '/people/users/top/page/3',
      '/languages/top/page/2',
      '/packages/npm/top/page/2'
    )
    expect(paths).not_to include(
      '/people/users/top/page/4',
      '/languages/top/page/3',
      '/packages/npm/top/page/3'
    )
  end
end
