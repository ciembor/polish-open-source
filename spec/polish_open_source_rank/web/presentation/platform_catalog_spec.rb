# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::PlatformCatalog do
  subject(:catalog) { described_class.new }

  it 'returns platform display names and icon paths' do
    expect(catalog.name('gitlab')).to eq('GitLab')
    expect(catalog.icon_path('codeberg')).to eq('/icons/codeberg.svg')
  end

  it 'uses GitHub as the fallback platform' do
    expect(catalog.name('unknown')).to eq('GitHub')
    expect(catalog.icon_path('unknown')).to eq('/icons/github.svg')
  end
end
