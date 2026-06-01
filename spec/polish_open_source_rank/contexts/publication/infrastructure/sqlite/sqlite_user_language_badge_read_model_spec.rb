# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Infrastructure::SQLite::SQLiteUserLanguageBadgeReadModel do
  subject(:read_model) { described_class.new(database) }

  let(:database) { instance_double(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database) }

  it 'stays disabled until the feature is enabled again' do
    allow(database).to receive(:fetch_all)

    expect(read_model.top_badge(platform: 'github', user_id: 1, period_start: Date.new(2026, 4, 1))).to be_nil
    expect(database).not_to have_received(:fetch_all)
  end

  it 'returns no badge without a public period when enabled' do
    stub_const("#{described_class}::ENABLED", true)
    allow(database).to receive(:fetch_all)

    expect(read_model.top_badge(platform: 'github', user_id: 1, period_start: nil)).to be_nil
    expect(database).not_to have_received(:fetch_all)
  end

  it 'returns no badge when the ranking query has no row' do
    stub_const("#{described_class}::ENABLED", true)
    allow(database).to receive(:fetch_all).and_return([])

    expect(read_model.top_badge(platform: 'github', user_id: 1, period_start: Date.new(2026, 4, 1))).to be_nil
  end

  it 'builds the best language badge from the ranking row when enabled' do
    stub_const("#{described_class}::ENABLED", true)
    allow(database).to receive(:fetch_all).and_return([{ language: 'Ruby', language_rank: 4 }])

    expect(read_model.top_badge(platform: 'github', user_id: 1, period_start: Date.new(2026, 4, 1))).to eq(
      {
        label: 'Polish RB Top 100',
        value: '4th',
        status: 'ranked',
        rank: 4
      }
    )
  end
end
