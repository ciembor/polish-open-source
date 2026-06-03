# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::MonthlySnapshotStore do
  it 'delegates monthly snapshot persistence and lifecycle responsibilities' do
    expect { exercise_monthly_snapshot_store_contract }.not_to raise_error
  end

  def exercise_monthly_snapshot_store_contract
    run_repository =
      instance_double(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRunRepository)
    candidate_queue =
      instance_double(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteCandidateQueue)
    snapshot_repository =
      instance_double(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRepository)
    ranking_retention =
      instance_double(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingRetention)
    snapshot_store = described_class.new(
      run_repository: run_repository,
      candidate_queue: candidate_queue,
      snapshot_repository: snapshot_repository,
      ranking_retention: ranking_retention
    )
    period = PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04')
    contributor_snapshot = instance_double(PolishOpenSourceRank::Contexts::Ranking::Domain::ContributorSnapshot)
    repository_snapshot = instance_double(PolishOpenSourceRank::Contexts::Ranking::Domain::RepositorySnapshot)
    organization_snapshot = instance_double(PolishOpenSourceRank::Contexts::Ranking::Domain::OrganizationSnapshot)
    organization_repository_snapshot =
      instance_double(PolishOpenSourceRank::Contexts::Ranking::Domain::OrganizationRepositorySnapshot)

    allow(run_repository).to receive(:create).with(period, refresh_platforms: ['github']).and_return(7)
    allow(run_repository).to receive(:finish).with(7)
    allow(run_repository).to receive(:fail).with(7, 'boom')
    allow(run_repository).to receive(:retryable_candidates?)
      .with(period, platforms: ['gitlab'], candidate_types: nil)
      .and_return(true)
    allow(candidate_queue).to receive(:record).with(
      period,
      login: 'alice',
      source_query: 'location:poland',
      platform: 'gitlab',
      source_id: 99,
      github_id: 99
    )
    allow(candidate_queue).to receive(:pending).with(period, limit: 12,
                                                             platform: 'gitlab').and_return([{ login: 'alice' }])
    allow(candidate_queue).to receive(:mark).with(period, 'gitlab', 'alice', 'processed', nil)
    allow(candidate_queue).to receive(:processed_user?).with(period, 'gitlab', 99).and_return(true)
    allow(candidate_queue).to receive(:record_organization).with(
      period,
      login: 'polish-org',
      source_query: 'location:poland',
      platform: 'gitlab',
      source_id: 55,
      github_id: 55
    )
    allow(candidate_queue).to receive(:pending_organizations).with(period, limit: 10, platform: 'gitlab')
                                                             .and_return([{ login: 'polish-org' }])
    allow(candidate_queue).to receive(:mark_organization).with(period, 'gitlab', 'polish-org', 'processed', nil)
    allow(candidate_queue).to receive(:processed_organization?).with(period, 'gitlab', 55).and_return(true)
    allow(snapshot_repository).to receive(:record_contributor_snapshot).with(contributor_snapshot)
    allow(snapshot_repository).to receive(:record_repository_snapshot).with(repository_snapshot)
    allow(snapshot_repository).to receive(:record_organization_snapshot).with(organization_snapshot)
    allow(snapshot_repository).to receive(:record_organization_repository_snapshot)
      .with(organization_repository_snapshot)
    allow(ranking_retention).to receive(:prune).with(period)

    expect(snapshot_store.create_run(period, refresh_platforms: ['github'])).to eq(7)
    snapshot_store.finish_run(7)
    snapshot_store.fail_run(7, 'boom')
    expect(snapshot_store.retryable_candidates?(period, platforms: ['gitlab'])).to be(true)
    snapshot_store.record_candidate(
      period,
      login: 'alice',
      source_query: 'location:poland',
      platform: 'gitlab',
      source_id: 99,
      github_id: 99
    )
    expect(snapshot_store.pending_candidates(period, limit: 12, platform: 'gitlab')).to eq([{ login: 'alice' }])
    snapshot_store.mark_candidate(period, 'gitlab', 'alice', 'processed')
    expect(snapshot_store.processed_user?(period, 'gitlab', 99)).to be(true)
    snapshot_store.record_organization_candidate(
      period,
      login: 'polish-org',
      source_query: 'location:poland',
      platform: 'gitlab',
      source_id: 55,
      github_id: 55
    )
    expect(snapshot_store.pending_organization_candidates(period, limit: 10, platform: 'gitlab')).to eq(
      [{ login: 'polish-org' }]
    )
    snapshot_store.mark_organization_candidate(period, 'gitlab', 'polish-org', 'processed')
    expect(snapshot_store.processed_organization?(period, 'gitlab', 55)).to be(true)
    snapshot_store.record_contributor_snapshot(contributor_snapshot)
    snapshot_store.record_repository_snapshot(repository_snapshot)
    snapshot_store.record_organization_snapshot(organization_snapshot)
    snapshot_store.record_organization_repository_snapshot(organization_repository_snapshot)
    snapshot_store.prune_rankings(period)
  end
end
