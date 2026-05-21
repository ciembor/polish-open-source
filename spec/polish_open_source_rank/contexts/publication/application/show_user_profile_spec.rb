# frozen_string_literal: true

class UserProfileReadModel
  def user_profile(*) = nil
end

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Application::ShowUserProfile do
  it 'wraps profile rows in a profile page response model' do
    read_model = instance_double(
      UserProfileReadModel,
      user_profile: { login: 'alice', repositories: [{ full_name: 'alice/app' }], badges: [{ label: 'Elite' }] }
    )

    result = described_class.new(profile_read_model: read_model).call(
      platform: 'github',
      login: 'alice',
      period_start: '2026-04-01'
    )

    expect(result).to be_a(PolishOpenSourceRank::Contexts::Publication::Application::ProfilePage)
    expect(result.fetch(:login)).to eq('alice')
    expect(result.repositories).to eq([{ full_name: 'alice/app' }])
    expect(result.badges).to eq([{ label: 'Elite' }])
    expect(result.to_h).to include(login: 'alice')
  end
end
