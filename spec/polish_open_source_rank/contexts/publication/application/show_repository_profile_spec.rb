# frozen_string_literal: true

class RepositoryProfileReadModel
  def repository_profile(*) = nil
end

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Application::ShowRepositoryProfile do
  it 'wraps repository rows in a repository page response model' do
    read_model = instance_spy(RepositoryProfileReadModel)
    allow(read_model).to receive(:repository_profile)
      .with('github', 'alice/app', period_start: '2026-04-01')
      .and_return(full_name: 'alice/app', polish_repo_badge: { label: 'Polish .rb Repo' })

    result = described_class.new(profile_read_model: read_model).call(
      platform: 'github',
      owner: 'alice',
      name: 'app',
      period_start: '2026-04-01'
    )

    expect(result).to be_a(PolishOpenSourceRank::Contexts::Publication::Application::RepositoryPage)
    expect(result.fetch(:full_name)).to eq('alice/app')
    expect(result.badge).to eq(label: 'Polish .rb Repo')
    expect(read_model).to have_received(:repository_profile)
      .with('github', 'alice/app', period_start: '2026-04-01')
  end

  it 'rejects ambiguous repository owner and name route parts' do
    read_model = instance_double(RepositoryProfileReadModel)

    expect do
      described_class.new(profile_read_model: read_model).call(
        platform: 'github',
        owner: 'alice/team',
        name: 'app',
        period_start: '2026-04-01'
      )
    end.to raise_error(ArgumentError, /Invalid login/)
  end
end
