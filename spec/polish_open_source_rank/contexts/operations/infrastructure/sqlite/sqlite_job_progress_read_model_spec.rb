# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteJobProgressReadModel do
  it 'keeps the operations read model behind the extracted namespace' do
    expect(described_class.superclass).to eq(PolishOpenSourceRank::Infrastructure::SQLiteJobProgress)
  end
end
