# frozen_string_literal: true

class JobProgressReadModel
  def job_progress(**) = nil
end

RSpec.describe PolishOpenSourceRank::Contexts::Operations::Application::ShowJobProgress do
  it 'reads job progress through the injected read model' do
    now = Time.utc(2026, 4, 1, 10, 0, 0)
    read_model = instance_double(JobProgressReadModel, job_progress: { generated_at: now.iso8601 })

    result = described_class.new(read_model: read_model).call(now: now)

    expect(result).to eq(generated_at: '2026-04-01T10:00:00Z')
    expect(read_model).to have_received(:job_progress).with(now: now)
  end
end
