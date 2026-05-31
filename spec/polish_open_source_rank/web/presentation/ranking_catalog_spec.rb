# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::RankingCatalog do
  subject(:catalog) { described_class.new }

  it 'describes supported ranking pages' do
    descriptor = catalog.descriptor('users', 'active')

    expect(catalog.include?('users', 'active')).to be(true)
    expect(descriptor.column).to eq(:merged_pull_requests_count)
    expect(descriptor.title_key).to eq('rankings.title.users.active')
    expect(descriptor.label_key).to eq('rankings.metric.merged_pull_requests')
    expect(catalog.descriptor('organizations', 'members').column).to eq(:members_count)
    expect(catalog.descriptor('organizations', 'members').title_key).to eq('rankings.title.organizations.members')
    expect(catalog.descriptor('organizations', 'members').label_key).to eq('rankings.metric.members')
  end

  it 'rejects unsupported ranking combinations' do
    expect(catalog.include?('repositories', 'active')).to be(false)
    expect(catalog.include?('users', 'members')).to be(false)
    expect { catalog.descriptor('repositories', 'active') }.to raise_error(KeyError)
  end
end
