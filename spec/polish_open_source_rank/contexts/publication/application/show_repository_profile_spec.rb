# frozen_string_literal: true

class RepositoryProfileReadModel
  def repository_profile(*) = nil
end

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Application::ShowRepositoryProfile do
  it 'wraps repository rows in a repository page response model' do
    read_model = instance_double(
      RepositoryProfileReadModel,
      repository_profile: { full_name: 'alice/app', polish_repo_badge: { label: 'Polish .rb Repo' } }
    )

    result = described_class.new(profile_read_model: read_model).call(
      platform: 'github',
      owner: 'alice',
      name: 'app',
      period_start: '2026-04-01'
    )

    expect(result).to be_a(PolishOpenSourceRank::Contexts::Publication::Application::RepositoryPage)
    expect(result.fetch(:full_name)).to eq('alice/app')
    expect(result.badge).to eq(label: 'Polish .rb Repo')
  end
end
