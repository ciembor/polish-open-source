# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Shared::Domain::PeriodStart do
  it 'normalizes persisted period start values' do
    expect(described_class.new('2026-04-01').to_s).to eq('2026-04-01')
  end

  it 'rejects missing and malformed values' do
    expect { described_class.new(nil) }.to raise_error(ArgumentError, /Invalid period_start/)
    expect { described_class.new('2026-99-01') }.to raise_error(ArgumentError, /Invalid period_start/)
  end
end
