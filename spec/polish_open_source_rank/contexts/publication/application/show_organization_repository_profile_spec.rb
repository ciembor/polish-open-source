# frozen_string_literal: true

class OrganizationRepositoryProfileReadModel
  def organization_repository_profile(*) = nil
end

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Application::ShowOrganizationRepositoryProfile do
  it 'wraps organization repository rows in a repository page response model' do
    read_model = instance_double(
      OrganizationRepositoryProfileReadModel,
      organization_repository_profile: {
        full_name: 'polish-org/toolkit',
        polish_repo_badge: { label: 'Polish Repo' }
      }
    )

    result = described_class.new(profile_read_model: read_model).call(
      platform: 'github',
      owner: 'polish-org',
      name: 'toolkit',
      period_start: '2026-04-01'
    )

    expect(result).to be_a(PolishOpenSourceRank::Contexts::Publication::Application::RepositoryPage)
    expect(result.fetch(:full_name)).to eq('polish-org/toolkit')
    expect(result.badge).to eq(label: 'Polish Repo')
  end
end
