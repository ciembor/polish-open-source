# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Community::Application::DiscordInviteUseDetector do
  it 'detects increased and consumed one-use Discord invites' do
    detector = described_class.new

    expect(detector.used_code({ 'a' => 0 }, { 'a' => 1 })).to eq('a')
    expect(detector.used_code({ 'one-use' => 0 }, {})).to eq('one-use')
  end

  it 'ignores unchanged or ambiguous invite changes' do
    detector = described_class.new

    expect(detector.used_code({ 'a' => 1 }, { 'a' => 1 })).to be_nil
    expect(detector.used_code({ 'a' => 0, 'b' => 0 }, { 'a' => 1, 'b' => 1 })).to be_nil
  end
end
