# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Shared::Domain::SourceIdentity do
  it 'keeps platform and source id together' do
    identity = described_class.new(platform: 'gitlab', source_id: 123)

    expect(identity.platform_key).to eq('gitlab')
    expect(identity.source_id).to eq(123)
    expect { described_class.new(platform: 'github', source_id: nil) }.to raise_error(ArgumentError)
  end

  it 'does not expose mutable struct writers' do
    identity = described_class.new(platform: 'github', source_id: 123)

    expect(identity).not_to respond_to(:platform=)
    expect(identity).not_to respond_to(:[]=)
  end
end
