# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Application do
  let(:read_model) do
    double(
      'PackageRankingReadModel',
      ecosystem_cards: [
        { ecosystem: 'npm' },
        { ecosystem: 'rubygems' },
        { ecosystem: 'pypi' }
      ],
      rankings: { downloads_30d: [{ package_name: 'tool' }] },
      ranked_packages: [{ package_name: 'tool' }],
      package_profile: { package_name: 'tool' }
    )
  end

  it 'shows package index ecosystems for a period' do
    result = described_class::ShowPackageIndex.new(package_ranking_read_model: read_model).call(
      period_start: '2026-04-01'
    )

    expect(result).to eq([{ ecosystem: 'npm' }, { ecosystem: 'rubygems' }, { ecosystem: 'pypi' }])
  end

  it 'returns empty package index for missing period' do
    result = described_class::ShowPackageIndex.new(package_ranking_read_model: read_model).call(period_start: nil)

    expect(result).to eq([])
  end

  it 'shows ecosystem rankings' do
    result = described_class::ShowPackageEcosystemRankings.new(package_ranking_read_model: read_model).call(
      ecosystem: 'npm',
      period_start: '2026-04-01',
      limit: 10
    )

    expect(result).to eq(downloads_30d: [{ package_name: 'tool' }])
    expect(read_model).to have_received(:rankings).with(ecosystem: 'npm', period_start: '2026-04-01', limit: 10)
  end

  it 'shows a package ranking detail' do
    result = described_class::ShowPackageRankingDetail.new(package_ranking_read_model: read_model).call(
      ecosystem: 'npm',
      metric: 'downloads_total',
      period_start: '2026-04-01',
      limit: 20
    )

    expect(result).to eq([{ package_name: 'tool' }])
    expect(read_model).to have_received(:ranked_packages).with(
      ecosystem: 'npm',
      period_start: '2026-04-01',
      metric: 'downloads_total',
      limit: 20
    )
  end

  it 'shows a package profile' do
    result = described_class::ShowPackageProfile.new(package_ranking_read_model: read_model).call(
      ecosystem: 'npm',
      package_name: 'tool',
      period_start: '2026-04-01'
    )

    expect(result).to eq(package_name: 'tool')
  end
end
