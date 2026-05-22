# frozen_string_literal: true

class PublicationProfileReadModel
  def user_profile(*) = nil

  def repository_profile(*) = nil
end

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Application::RenderBadge do
  it 'wraps user badges in a badge response model' do
    read_model = instance_double(
      PublicationProfileReadModel,
      user_profile: { profile_badge: { label: 'Polish Open Source', value: '1st' } }
    )

    result = described_class.new(profile_read_model: read_model).user(
      platform: 'github',
      login: 'alice',
      period_start: '2026-04-01'
    )

    expect(result).to be_a(PolishOpenSourceRank::Contexts::Publication::Application::BadgeView)
    expect(result.fetch(:label)).to eq('Polish Open Source')
  end

  it 'wraps repository badges in a badge response model' do
    read_model = instance_double(
      PublicationProfileReadModel,
      repository_profile: { polish_repo_badge: { label: 'Polish Top 100', value: '1st' } }
    )

    result = described_class.new(profile_read_model: read_model).repository(
      platform: 'github',
      owner: 'alice',
      name: 'app',
      period_start: '2026-04-01'
    )

    expect(result).to be_a(PolishOpenSourceRank::Contexts::Publication::Application::BadgeView)
    expect(result.fetch(:value)).to eq('1st')
  end
end
