# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Shared::Domain::RepositoryFullName do
  it 'keeps repository owner and name as one validated identity' do
    full_name = described_class.build(owner: 'alice', name: 'app')

    expect(full_name.owner).to eq('alice')
    expect(full_name.name).to eq('app')
    expect(full_name.to_s).to eq('alice/app')
    expect(described_class.parse('alice/app').to_s).to eq(full_name.to_s)
  end

  it 'rejects ambiguous route-shaped repository identities' do
    expect { described_class.build(owner: '', name: 'app') }.to raise_error(ArgumentError, 'login is required')
    expect { described_class.build(owner: 'alice/team', name: 'app') }.to raise_error(ArgumentError)
    expect { described_class.build(owner: 'alice', name: '') }.to raise_error(ArgumentError)
    expect { described_class.parse('alice/app/extra') }.to raise_error(ArgumentError)
  end
end
