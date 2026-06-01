# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Shared::Domain::Period do
  it 'builds the previous calendar month' do
    period = described_class.previous_month(Date.new(2026, 5, 16))

    expect(period.start_date).to eq(Date.new(2026, 4, 1))
    expect(period.end_date).to eq(Date.new(2026, 5, 1))
    expect(period.key).to eq('2026-04')
  end

  it 'parses a month and checks time membership' do
    period = described_class.parse('2026-02')

    expect(period.cover_time?(Time.parse('2026-02-28T23:59:59Z'))).to be(true)
    expect(period.cover_time?(Time.parse('2026-03-01T00:00:00Z'))).to be(false)
  end

  it 'is immutable once built' do
    period = described_class.parse('2026-02')

    expect(period).not_to respond_to(:start_date=)
    expect(period).not_to respond_to(:[]=)
  end
end
