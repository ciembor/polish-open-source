# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Domain::LocationClassifier do
  subject(:classifier) { described_class.new }

  it 'classifies country variants and city variants as Polish locations', :aggregate_failures do
    expect(classifier.call('Krakow, Poland')).to have_attributes(city: 'Kraków', city_slug: 'krakow', country: 'Poland')
    expect(classifier.call('cracow, poland')).to have_attributes(city: 'Kraków', country: 'Poland')
    expect(classifier.call('Warszawa, Polska')).to have_attributes(city: 'Warszawa', country: 'Poland')
    expect(classifier.call('Warsaw')).to have_attributes(city: 'Warszawa', country: 'Poland')
    expect(classifier.call('Łódź')).to have_attributes(city: 'Łódź', country: 'Poland')
    expect(classifier.call('Gdansk')).to have_attributes(city: 'Gdańsk', country: 'Poland')
    expect(classifier.call('Bielsko Biala')).to have_attributes(city: 'Bielsko-Biała', country: 'Poland')
    expect(classifier.call('Ruda Slaska')).to have_attributes(city: 'Ruda Śląska', country: 'Poland')
    expect(classifier.call('Dabrowa Gornicza')).to have_attributes(city: 'Dąbrowa Górnicza', country: 'Poland')
    expect(classifier.call('Gorzów Wlkp')).to have_attributes(city: 'Gorzów Wielkopolski', country: 'Poland')
    expect(classifier.call('Elblag')).to have_attributes(city: 'Elbląg', country: 'Poland')
    expect(classifier.call('Plock')).to have_attributes(city: 'Płock', country: 'Poland')
  end

  it 'rejects unrelated locations' do
    match = classifier.call('Berlin, Germany')

    expect(match).to have_attributes(city: nil, city_slug: nil, country: nil, raw: 'Berlin, Germany')
    expect(match).not_to be_polish
  end

  it 'keeps multi-country users accepted through the default classification' do
    expect(classifier.call('Warsaw, Poland / Berlin, Germany')).to have_attributes(
      city: 'Warszawa',
      country: 'Poland'
    )
  end

  it 'rejects organization locations that include another country' do
    expect(classifier.without_foreign_countries('Warsaw, Poland / Berlin, Germany')).to have_attributes(
      city: nil,
      country: nil,
      raw: 'Warsaw, Poland / Berlin, Germany'
    )
    expect(classifier.without_foreign_countries('Krakow, Poland, USA')).not_to be_polish
    expect(classifier.without_foreign_countries('Warsaw, United States')).not_to be_polish
  end

  it 'exposes stable scopes and search terms' do
    catalog = PolishOpenSourceRank::Contexts::Ranking::Domain::LocationCatalog

    expect(catalog.city_slugs).to include('krakow', 'wroclaw', 'warszawa', 'lodz')
    expect(catalog.city_name('poznan')).to eq('Poznań')
    expect(catalog.scopes.first).to eq(slug: 'poland', name: 'Polska', type: :country)
    expect(catalog.search_terms).to include('Polska', 'poland', 'Cracow', 'Poznan', 'Dabrowa Gornicza')
  end

  it 'orders supported city scopes by population descending' do
    catalog = PolishOpenSourceRank::Contexts::Ranking::Domain::LocationCatalog

    expect(catalog::CITIES.map { |city| city.fetch(:name) }).to eq(
      [
        'Warszawa', 'Kraków', 'Wrocław', 'Łódź', 'Poznań', 'Gdańsk', 'Szczecin', 'Lublin',
        'Bydgoszcz', 'Białystok', 'Katowice', 'Gdynia', 'Częstochowa', 'Rzeszów', 'Toruń',
        'Radom', 'Sosnowiec', 'Kielce', 'Gliwice', 'Olsztyn', 'Bielsko-Biała', 'Zabrze',
        'Bytom', 'Zielona Góra', 'Rybnik', 'Ruda Śląska', 'Opole', 'Tychy',
        'Gorzów Wielkopolski', 'Dąbrowa Górnicza', 'Elbląg', 'Płock', 'Koszalin', 'Tarnów'
      ]
    )
    expect(catalog.primary_city_scopes.map { |city| city.fetch(:name) }).to eq(
      %w[Warszawa Kraków Wrocław Łódź Poznań]
    )
    expect(catalog.secondary_city_scopes.first.fetch(:name)).to eq('Gdańsk')
    expect(catalog.secondary_city_scopes.last.fetch(:name)).to eq('Tarnów')
  end
end
