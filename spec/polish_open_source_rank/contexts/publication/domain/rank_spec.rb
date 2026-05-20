# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Domain::Rank do
  it 'formats ordinal places' do
    expect([1, 2, 3, 4, 11, 12, 13, 21].map { |rank| described_class.place(rank) }).to eq(
      %w[1st 2nd 3rd 4th 11th 12th 13th 21st]
    )
  end
end
