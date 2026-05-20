# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Shared::Domain::Period do
  it 'parses and formats month periods' do
    period = described_class.parse('2026-04')

    expect(period.start_date).to eq(Date.new(2026, 4, 1))
    expect(period.end_date).to eq(Date.new(2026, 5, 1))
    expect(period.key).to eq('2026-04')
    expect(period.cover_time?(Time.parse('2026-04-30T22:00:00Z'))).to be(true)
  end

  it 'builds previous calendar month' do
    expect(described_class.previous_month(Date.new(2026, 1, 8)).key).to eq('2025-12')
  end
end
