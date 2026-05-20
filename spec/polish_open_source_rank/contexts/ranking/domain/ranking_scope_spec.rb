# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Domain::RankingScope do
  it 'represents country and city ranking scopes' do
    country = described_class.poland
    city = described_class.new('krakow')

    expect(country).to be_country
    expect(city).not_to be_country
    expect(city.city_name).to eq('Kraków')
    expect { described_class.new('unknown') }.to raise_error(ArgumentError)
  end
end
