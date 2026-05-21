# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Domain::LocationClassifier do
  subject(:classifier) { described_class.new }

  it 'classifies country variants and city variants as Polish locations' do
    expect(classifier.call('Krakow, Poland')).to have_attributes(city: 'Kraków', city_slug: 'krakow', country: 'Poland')
    expect(classifier.call('cracow, poland')).to have_attributes(city: 'Kraków', country: 'Poland')
    expect(classifier.call('Warszawa, Polska')).to have_attributes(city: 'Warszawa', country: 'Poland')
    expect(classifier.call('Warsaw')).to have_attributes(city: 'Warszawa', country: 'Poland')
    expect(classifier.call('Łódź')).to have_attributes(city: 'Łódź', country: 'Poland')
    expect(classifier.call('Gdansk')).to have_attributes(city: 'Gdańsk', country: 'Poland')
  end

  it 'rejects unrelated locations' do
    match = classifier.call('Berlin, Germany')

    expect(match).to have_attributes(city: nil, city_slug: nil, country: nil, raw: 'Berlin, Germany')
    expect(match).not_to be_polish
  end

  it 'exposes stable scopes and search terms' do
    catalog = PolishOpenSourceRank::Contexts::Ranking::Domain::LocationCatalog

    expect(catalog.city_slugs).to include('krakow', 'wroclaw', 'warszawa', 'lodz')
    expect(catalog.city_name('poznan')).to eq('Poznań')
    expect(catalog.scopes.first).to eq(slug: 'poland', name: 'Polska', type: :country)
    expect(catalog.search_terms).to include('Polska', 'poland', 'Cracow', 'Poznan')
  end
end
