# frozen_string_literal: true

class OrganizationProfileReadModel
  def organization_profile(*) = nil
end

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Application::ShowOrganizationProfile do
  it 'wraps organization rows in a profile page response model' do
    read_model = instance_double(
      OrganizationProfileReadModel,
      organization_profile: {
        login: 'polish-org',
        repositories: [{ full_name: 'polish-org/toolkit' }],
        badges: [{ label: 'Polish Open Source Org' }]
      }
    )

    result = described_class.new(profile_read_model: read_model).call(
      platform: 'github',
      login: 'polish-org',
      period_start: '2026-04-01'
    )

    expect(result).to be_a(PolishOpenSourceRank::Contexts::Publication::Application::ProfilePage)
    expect(result.fetch(:login)).to eq('polish-org')
    expect(result.repositories).to eq([{ full_name: 'polish-org/toolkit' }])
    expect(result.badges).to eq([{ label: 'Polish Open Source Org' }])
  end
end
