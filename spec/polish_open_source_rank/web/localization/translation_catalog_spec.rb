# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Localization::TranslationCatalog do
  subject(:text) { described_class.load(root: PolishOpenSourceRank.root, locales: %w[en pl]) }

  it 'loads nested locale files and interpolates values' do
    expect(text.translate('en', 'nav.country')).to eq('Poland')
    expect(text.translate('pl', 'nav.country')).to eq('Polska')
    expect(text.translate('en', 'rankings.seo.description', scope: 'Krakow')).to include('for Krakow')
  end

  it 'keeps structured translation values when callers need them' do
    expect(text.translate('en', 'date.months').fetch(3)).to eq('April')
    expect(text.translate('pl', 'date.months').fetch(3)).to eq('kwiecień')
  end
end
