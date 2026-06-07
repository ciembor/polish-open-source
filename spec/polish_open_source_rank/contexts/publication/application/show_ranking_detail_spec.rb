# frozen_string_literal: true

class DetailRankingReadModel
  def ranked_user_metric(*) = [{ login: 'alice' }]

  def ranked_repository_metric(*) = [{ full_name: 'alice/app' }]

  def ranked_organization_metric(*) = [{ login: 'polish-org' }]

  def ranked_organization_repository_metric(*) = [{ full_name: 'polish-org/toolkit' }]
end

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Application::ShowRankingDetail do
  let(:read_model) do
    instance_double(
      DetailRankingReadModel,
      ranked_user_metric: [{ login: 'alice' }],
      ranked_repository_metric: [{ full_name: 'alice/app' }],
      ranked_organization_metric: [{ login: 'polish-org' }],
      ranked_organization_repository_metric: [{ full_name: 'polish-org/toolkit' }]
    )
  end

  it 'dispatches ranking detail queries by public kind' do
    use_case = described_class.new(ranking_read_model: read_model)

    expect(use_case.call(scope: 'poland', kind: 'users', metric: 'top', period_start: '2026-04-01')).to eq(
      [{ login: 'alice' }]
    )
    expect(use_case.call(scope: 'poland', kind: 'repositories', metric: 'top', period_start: '2026-04-01')).to eq(
      [{ full_name: 'alice/app' }]
    )
    expect(use_case.call(scope: 'poland', kind: 'organizations', metric: 'top', period_start: '2026-04-01')).to eq(
      [{ login: 'polish-org' }]
    )
    expect(
      use_case.call(scope: 'poland', kind: 'organization-repositories', metric: 'top', period_start: '2026-04-01')
    ).to eq([{ full_name: 'polish-org/toolkit' }])
    expect(use_case.call(scope: 'poland', kind: 'users', metric: 'top', period_start: nil)).to eq([])
    expect(read_model).to have_received(:ranked_user_metric).with(
      'poland',
      '2026-04-01',
      :user_top,
      limit: 100,
      offset: 0
    )
  end
end
