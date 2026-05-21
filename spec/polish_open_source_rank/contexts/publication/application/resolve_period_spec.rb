# frozen_string_literal: true

class PeriodReadModel
  def latest_period = nil

  def recorded_period?(*) = false
end

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Application::ResolvePeriod do
  it 'returns the latest public period for the latest alias' do
    read_model = instance_double(PeriodReadModel, latest_period: '2026-04-01')

    result = described_class.new(period_read_model: read_model).call(period_slug: 'latest')

    expect(result).to eq('2026-04-01')
  end

  it 'resolves recorded month slugs to period starts' do
    read_model = instance_double(PeriodReadModel, recorded_period?: true)
    allow(read_model).to receive(:latest_period)

    result = described_class.new(period_read_model: read_model).call(period_slug: '2026-04')

    expect(result).to eq('2026-04-01')
    expect(read_model).to have_received(:recorded_period?).with('2026-04-01')
  end

  it 'rejects unknown or malformed period slugs' do
    read_model = instance_double(PeriodReadModel, latest_period: nil, recorded_period?: false)
    use_case = described_class.new(period_read_model: read_model)

    expect(use_case.call(period_slug: '2026-13')).to be_nil
    expect(use_case.call(period_slug: 'nope')).to be_nil
  end
end
