# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::RankingCatalog do
  subject(:catalog) { described_class.new }

  it 'describes supported ranking pages' do
    descriptor = catalog.descriptor('users', 'active')

    expect(catalog.include?('users', 'active')).to be(true)
    expect(descriptor.column).to eq(:public_activity_count)
    expect(descriptor.title_key).to eq('rankings.title.users.active')
    expect(descriptor.label_key).to eq('rankings.metric.events')
  end

  it 'rejects unsupported ranking combinations' do
    expect(catalog.include?('repositories', 'active')).to be(false)
    expect { catalog.descriptor('repositories', 'active') }.to raise_error(KeyError)
  end
end
