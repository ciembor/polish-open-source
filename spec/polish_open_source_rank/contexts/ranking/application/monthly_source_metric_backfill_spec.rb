# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Application::MonthlySourceMetricBackfill do
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }
  let(:logger) { StringIO.new }
  let(:work_events) { instance_double(PolishOpenSourceRank::Contexts::Operations::Application::JobWorkEventRecorder) }
  let(:store) { instance_double(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::MonthlySnapshotStore) }

  before do
    stub_const('GitHubSource', Class.new)
    stub_const('GitLabSource', Class.new)
    allow(work_events).to receive(:record_timed).and_yield
    allow(work_events).to receive(:successful_subject_ids).and_return(Set.new)
  end

  it 'continues after one source fails to refresh merged pull requests' do
    failing_source = instance_double(GitHubSource, platform: 'github')
    passing_source = instance_double(GitLabSource, platform: 'gitlab')
    allow(store).to receive(:user_stats_for_period).with(period, platform: 'github').and_raise('boom')
    allow(store).to receive(:user_stats_for_period).with(period, platform: 'gitlab')
                                                   .and_return([{ source_id: 2, user_github_id: 2, login: 'bob' }])
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

  it 'continues after one user refresh fails inside the same source' do
    source = instance_double(GitHubSource, platform: 'github')
    allow(store).to receive(:user_stats_for_period).with(period, platform: 'github').and_return(
      [
        { source_id: 1, user_github_id: 1, login: 'bad-user' },
        { source_id: 2, user_github_id: 2, login: 'good-user' }
      ]
    )
    allow(source).to receive(:merged_pull_requests_count).with(hash_including(login: 'bad-user'), period)
                                                         .and_raise('boom')
    allow(source).to receive(:merged_pull_requests_count).with(hash_including(login: 'good-user'), period)
                                                         .and_return(9)
    allow(store).to receive(:record_user_stats)

    described_class.new(store: store, sources: [source], logger: logger, work_events: work_events)
                   .call(period, refresh_user_merged_prs: true)

    expect(store).to have_received(:record_user_stats).with(
      hash_including(login: 'good-user', merged_pull_requests_count: 9)
    )
    expect(logger.string).to include('refresh merged pull requests skipped for bad-user: RuntimeError: boom')
  end

  it 'skips users that were already refreshed in previous backfill attempts' do
    source = instance_double(GitHubSource, platform: 'github')
    allow(store).to receive(:user_stats_for_period).with(period, platform: 'github').and_return(
      [
        { source_id: 1, user_github_id: 1, login: 'done-user' },
        { source_id: 2, user_github_id: 2, login: 'pending-user' }
      ]
    )
    allow(work_events).to receive(:successful_subject_ids).with(
      {
        period_start: '2026-04-01',
        job_kind: 'monthly',
        stage: 'user_merged_pull_requests',
        unit_kind: 'user',
        platform: 'github'
      }
    ).and_return(Set['1'])
    allow(source).to receive(:merged_pull_requests_count).with(hash_including(login: 'pending-user'), period)
                                                         .and_return(9)
    allow(store).to receive(:record_user_stats)

    described_class.new(store: store, sources: [source], logger: logger, work_events: work_events)
                   .call(period, refresh_user_merged_prs: true)

    expect(source).not_to have_received(:merged_pull_requests_count).with(hash_including(login: 'done-user'), period)
    expect(store).to have_received(:record_user_stats).with(
      hash_including(login: 'pending-user', merged_pull_requests_count: 9)
    )
  end

  it 'skips organizations that were already refreshed in previous backfill attempts' do
    source = instance_double(GitHubSource, platform: 'github', supports_organizations?: true)
    allow(store).to receive(:organization_stats_for_period).with(period, platform: 'github').and_return(
      [
        { source_id: 1, organization_github_id: 1, login: 'done-org' },
        { source_id: 2, organization_github_id: 2, login: 'pending-org' }
      ]
    )
    allow(work_events).to receive(:successful_subject_ids).with(
      {
        period_start: '2026-04-01',
        job_kind: 'monthly',
        stage: 'organization_members',
        unit_kind: 'organization',
        platform: 'github'
      }
    ).and_return(Set['1'])
    allow(source).to receive(:organization_members_count).with(hash_including(login: 'pending-org')).and_return(3)
    allow(store).to receive(:record_organization_stats)

    described_class.new(store: store, sources: [source], logger: logger, work_events: work_events)
                   .call(period, refresh_organization_members: true)

    expect(source).not_to have_received(:organization_members_count).with(hash_including(login: 'done-org'))
    expect(store).to have_received(:record_organization_stats).with(
      hash_including(login: 'pending-org', members_count: 3)
    )
  end

  it 'skips organization merged pull requests already refreshed in previous backfill attempts' do
    source = instance_double(GitHubSource, platform: 'github', supports_organizations?: true)
    allow(store).to receive(:organization_stats_for_period).with(period, platform: 'github').and_return(
      [
        { source_id: 1, organization_github_id: 1, login: 'done-org' },
        { source_id: 2, organization_github_id: 2, login: 'pending-org' }
      ]
    )
    allow(work_events).to receive(:successful_subject_ids).with(
      {
        period_start: '2026-04-01',
        job_kind: 'monthly',
        stage: 'organization_merged_pull_requests',
        unit_kind: 'organization',
        platform: 'github'
      }
    ).and_return(Set['1'])
    allow(source).to receive(:organization_merged_pull_requests_count)
      .with(hash_including(login: 'pending-org'), period)
      .and_return(11)
    allow(store).to receive(:record_organization_stats)

    described_class.new(store: store, sources: [source], logger: logger, work_events: work_events)
                   .call(period, refresh_organization_merged_prs: true)

    expect(source).not_to have_received(:organization_merged_pull_requests_count)
      .with(hash_including(login: 'done-org'), period)
    expect(store).to have_received(:record_organization_stats).with(
      hash_including(login: 'pending-org', merged_pull_requests_count: 11)
    )
  end

  it 'refreshes organization repository stars from previous monthly stats' do
    source = instance_double(GitHubSource, platform: 'github', supports_organizations?: true)
    allow(work_events).to receive(:successful_subject_ids).with(
      {
        period_start: '2026-04-01',
        job_kind: 'monthly',
        stage: 'organization_repository_stars',
        unit_kind: 'platform',
        platform: 'github'
      }
    ).and_return(Set.new)
    allow(store).to receive(:refresh_organization_repository_star_deltas_from_previous_stats)
    allow(store).to receive(:refresh_organization_repository_metrics)

    described_class.new(store: store, sources: [source], logger: logger, work_events: work_events)
                   .call(period, refresh_organization_stars: true)

    expect(store).to have_received(:refresh_organization_repository_star_deltas_from_previous_stats)
      .with(period, platform: 'github')
    expect(store).to have_received(:refresh_organization_repository_metrics).with(period, platform: 'github')
  end

  it 'skips organization repository stars already refreshed in previous backfill attempts' do
    source = instance_double(GitHubSource, platform: 'github', supports_organizations?: true)
    allow(work_events).to receive(:successful_subject_ids).with(
      {
        period_start: '2026-04-01',
        job_kind: 'monthly',
        stage: 'organization_repository_stars',
        unit_kind: 'platform',
        platform: 'github'
      }
    ).and_return(Set['github'])
    allow(store).to receive(:refresh_organization_repository_star_deltas_from_previous_stats)
    allow(store).to receive(:refresh_organization_repository_metrics)

    described_class.new(store: store, sources: [source], logger: logger, work_events: work_events)
                   .call(period, refresh_organization_stars: true)

    expect(store).not_to have_received(:refresh_organization_repository_star_deltas_from_previous_stats)
    expect(store).not_to have_received(:refresh_organization_repository_metrics)
  end

  it 'stops worker threads when joining source refreshes raises' do
    source_threads = instance_double(
      PolishOpenSourceRank::Contexts::Ranking::Application::MonthlySourceSnapshotRunner::SourceThreads,
      errors: []
    )
    allow(source_threads).to receive(:join).and_raise('interrupted')
    allow(source_threads).to receive(:stop)
    allow(PolishOpenSourceRank::Contexts::Ranking::Application::MonthlySourceSnapshotRunner::SourceThreads)
      .to receive(:start).and_return(source_threads)

    backfill = described_class.new(store: store, sources: [], logger: logger, work_events: work_events)

    expect do
      backfill.call(period, refresh_user_merged_prs: true)
    end.to raise_error(RuntimeError, 'interrupted')

    expect(source_threads).to have_received(:stop)
  end
end
