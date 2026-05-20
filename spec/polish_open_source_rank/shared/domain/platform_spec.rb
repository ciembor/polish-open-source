# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Shared::Domain::Platform do
  it 'normalizes supported platforms and rejects unknown ones' do
    platform = described_class.coerce('github')

    expect(platform.to_s).to eq('github')
    expect(platform).to eq('github')
    expect { described_class.new('bitbucket') }.to raise_error(ArgumentError, /Unsupported platform/)
  end
end
