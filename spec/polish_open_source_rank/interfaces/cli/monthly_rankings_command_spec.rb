# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Interfaces::CLI::MonthlyRankingsCommand do
  it 'runs a monthly job with injected persistence and sources' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    allow(job).to receive(:call)

    described_class.call(['--month', '2026-04'], job: job, output: output)

    expect(job).to have_received(:call).with(have_attributes(key: '2026-04'), refresh: false)
    expect(output.string).to include('Finished monthly ranking run for 2026-04')
  end

  it 'passes explicit refresh requests to the monthly job' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    allow(job).to receive(:call)

    described_class.call(['--month', '2026-04', '--refresh'], job: job, output: output)

    expect(job).to have_received(:call).with(have_attributes(key: '2026-04'), refresh: true)
  end

  it 'passes an explicit scope to the monthly job' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    allow(job).to receive(:call)

    described_class.call(['--month', '2026-04', '--scope', 'organizations'], job: job, output: output)

    expect(job).to have_received(:call).with(
      have_attributes(key: '2026-04'),
      refresh: false,
      scope: :organizations
    )
  end

  it 'turns process stop signals into job-visible interruptions' do
    output = StringIO.new
    term_handler = nil
    previous_handlers = []
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    allow(Signal).to receive(:trap).and_wrap_original do |original, signal, handler = nil, &block|
      if block
        term_handler = block if signal == 'TERM'
        previous_handlers << signal
        'DEFAULT'
      else
        original.call(signal, handler)
      end
    end
    allow(job).to receive(:call) { term_handler.call }

    expect do
      described_class.call(['--month', '2026-04'], job: job, output: output)
    end.to raise_error(PolishOpenSourceRank::Application::MonthlySnapshotInterrupted, 'Received SIGTERM')

    expect(job).to have_received(:call).with(have_attributes(key: '2026-04'), refresh: false)
    expect(output.string).to be_empty
    expect(Signal).to have_received(:trap).with('INT', 'DEFAULT')
    expect(Signal).to have_received(:trap).with('TERM', 'DEFAULT')
    expect(previous_handlers).to eq(%w[INT TERM])
  end
end
