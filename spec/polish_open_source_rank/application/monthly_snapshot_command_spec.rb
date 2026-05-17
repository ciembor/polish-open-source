# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Application::MonthlySnapshotCommand do
  it 'runs a monthly job with injected persistence and sources' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Application::MonthlySnapshotJob)
    allow(job).to receive(:call)

    described_class.call(['--month', '2026-04'], job: job, output: output)

    expect(job).to have_received(:call).with(have_attributes(key: '2026-04'))
    expect(output.string).to include('Finished monthly ranking run for 2026-04')
  end
end
