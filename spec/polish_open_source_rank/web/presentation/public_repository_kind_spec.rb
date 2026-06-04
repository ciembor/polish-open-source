# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::PublicRepositoryKind do
  it 'maps public route slugs to repository kind keys' do
    expect(described_class.key_for_slug('users')).to eq('user')
    expect(described_class.key_for_slug('organizations')).to eq('organization')
    expect(described_class.key_for_slug('repositories')).to be_nil
  end

  it 'rejects unsupported public repository kind slugs' do
    expect { described_class.key_for_slug('people') }.to raise_error(KeyError)
  end
end
