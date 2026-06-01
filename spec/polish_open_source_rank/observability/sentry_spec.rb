# frozen_string_literal: true

TestSentryConfiguration = Struct.new(
  :sentry_dsn,
  :sentry_runtime_environment,
  :sentry_release,
  :sentry_traces_sample_rate,
  keyword_init: true
) do
  def sentry_enabled? = true
end

RSpec.describe PolishOpenSourceRank::Observability::Sentry do
  after do
    Sentry.close if defined?(Sentry) && Sentry.initialized?
  end

  it 'configures Sentry once from application configuration' do
    configuration = config(release: 'abc123')

    described_class.configure(configuration)
    described_class.configure(configuration)

    sentry_config = Sentry.configuration
    expect(sentry_config.dsn.to_s).to include('public@example.com')
    expect(sentry_config.environment).to eq('test-observability')
    expect(sentry_config.release).to eq('abc123')
    expect(sentry_config.traces_sample_rate).to eq(0.25)
  end

  it 'adds request scope tags and captures exceptions through Sentry' do
    described_class.configure(config)
    scope = instance_double(Sentry::Scope, set_tags: nil, set_context: nil)
    error = RuntimeError.new('boom')
    allow(Sentry).to receive(:with_scope).and_yield(scope)
    allow(Sentry).to receive(:capture_exception)

    result = described_class.with_request_scope(request_id: 'request-1', path_template: '/latest') { :ok }
    described_class.capture_exception(error, context: { request_id: 'request-1' })

    expect(result).to eq(:ok)
    expect(scope).to have_received(:set_tags).with(request_id: 'request-1', path_template: '/latest')
    expect(scope).to have_received(:set_context).with('polish_open_source_rank', request_id: 'request-1')
    expect(Sentry).to have_received(:capture_exception).with(error)
  end

  it 'wraps monitored jobs in Sentry check-ins' do
    described_class.configure(config)
    allow(Sentry).to receive(:capture_check_in)

    expect(described_class.monitor_check_in('monthly-rankings') { :finished }).to eq(:finished)

    expect(Sentry).to have_received(:capture_check_in).with('monthly-rankings', :in_progress)
    expect(Sentry).to have_received(:capture_check_in).with('monthly-rankings', :ok)
  end

  it 'marks monitored jobs as failed when they raise' do
    described_class.configure(config)
    allow(Sentry).to receive(:capture_check_in)

    expect do
      described_class.monitor_check_in('package-rankings') { raise 'failed' }
    end.to raise_error(RuntimeError, 'failed')

    expect(Sentry).to have_received(:capture_check_in).with('package-rankings', :error)
  end

  def config(release: '')
    TestSentryConfiguration.new(
      sentry_dsn: 'https://public@example.com/1',
      sentry_runtime_environment: 'test-observability',
      sentry_release: release,
      sentry_traces_sample_rate: 0.25
    )
  end
end
