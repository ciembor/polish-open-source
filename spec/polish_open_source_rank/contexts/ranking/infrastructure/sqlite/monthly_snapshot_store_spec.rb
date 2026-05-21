# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::MonthlySnapshotStore do
  # rubocop:disable RSpec/ExampleLength
  it 'delegates monthly snapshot persistence and lifecycle responsibilities' do
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

    allow(run_repository).to receive(:create).with(period, refresh_platforms: ['github']).and_return(7)
    allow(run_repository).to receive(:finish).with(7)
    allow(run_repository).to receive(:fail).with(7, 'boom')
    allow(run_repository).to receive(:retryable_candidates?).with(period, platforms: ['gitlab']).and_return(true)
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
    allow(snapshot_repository).to receive(:record_contributor_snapshot).with(contributor_snapshot)
    allow(snapshot_repository).to receive(:record_repository_snapshot).with(repository_snapshot)
    allow(snapshot_repository).to receive(:previous_repository_stars).with(period, 'gitlab', 123).and_return(15)
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
    snapshot_store.record_contributor_snapshot(contributor_snapshot)
    snapshot_store.record_repository_snapshot(repository_snapshot)
    expect(snapshot_store.previous_repository_stars(period, 'gitlab', 123)).to eq(15)
    snapshot_store.prune_rankings(period)
  end
  # rubocop:enable RSpec/ExampleLength
end
