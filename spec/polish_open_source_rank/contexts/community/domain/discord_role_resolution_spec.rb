# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Community::Domain::DiscordRoleResolution do
  it 'exposes prepared managed and desired role ids' do
    resolution = described_class.new(
      role_ids: { 'DISCORD_ROLE_TOP_100_PL' => 'role-1' },
      managed_role_ids: %w[role-1 role-2]
    )

    expect(resolution.role_ids).to eq('DISCORD_ROLE_TOP_100_PL' => 'role-1')
    expect(resolution.managed_role_ids).to eq(%w[role-1 role-2])
  end
end
