# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Application::MonthlySourceMetricBackfill do
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }
  let(:logger) { StringIO.new }
  let(:work_events) { instance_double(PolishOpenSourceRank::Contexts::Operations::Application::JobWorkEventRecorder) }
  let(:store) { instance_double(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::MonthlySnapshotStore) }

  before do
    allow(work_events).to receive(:record_timed).and_yield
  end

  it 'continues after one source fails to refresh merged pull requests' do
    failing_source = instance_double(FakeJobGitHub, platform: 'github')
    passing_source = instance_double(FakeJobGitLab, platform: 'gitlab')
    allow(store).to receive(:user_stats_for_period).with(period, platform: 'github')
                                                   .and_return([{ source_id: 1, user_github_id: 1, login: 'alice' }])
    allow(store).to receive(:user_stats_for_period).with(period, platform: 'gitlab')
                                                   .and_return([{ source_id: 2, user_github_id: 2, login: 'bob' }])
    allow(failing_source).to receive(:merged_pull_requests_count).and_raise('boom')
    allow(passing_source).to receive(:merged_pull_requests_count).and_return(7)
    allow(store).to receive(:record_user_stats)

    described_class
      .new(
        store: store,
        sources: [failing_source, passing_source],
        logger: logger,
        work_events: work_events
      )
      .call(period, refresh_user_merged_prs: true)

    expect(store).to have_received(:record_user_stats).with(
      hash_including(login: 'bob', merged_pull_requests_count: 7)
    )
    expect(logger.string).to include('refresh merged pull requests failed: RuntimeError: boom')
  end

  it 'stops worker threads when joining source refreshes raises' do
    source_threads = instance_double(
      PolishOpenSourceRank::Contexts::Ranking::Application::MonthlySnapshotWorkflow::SourceThreads,
      errors: []
    )
    allow(source_threads).to receive(:join).and_raise('interrupted')
    allow(source_threads).to receive(:stop)
    allow(PolishOpenSourceRank::Contexts::Ranking::Application::MonthlySnapshotWorkflow::SourceThreads)
      .to receive(:start).and_return(source_threads)

    backfill = described_class.new(store: store, sources: [], logger: logger, work_events: work_events)

    expect do
      backfill.call(period, refresh_user_merged_prs: true)
    end.to raise_error(RuntimeError, 'interrupted')

    expect(source_threads).to have_received(:stop)
  end
end
