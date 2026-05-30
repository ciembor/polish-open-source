# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Operations::Application::StalledCrawlWatchdog do
  it 'interrupts the process when progress stays stale beyond the timeout' do
    now = 0.0
    heartbeat = PolishOpenSourceRank::Contexts::Operations::Application::ProgressHeartbeat.new(clock: -> { now })
    output = StringIO.new
    allow(Process).to receive(:pid).and_return(123)
    killed = false
    allow(Process).to receive(:kill) do
      killed = true
    end
    watchdog = described_class.new(
      heartbeat: heartbeat,
      output: output,
      label: 'Package crawl',
      timeout_seconds: 10,
      execution: {
        poll_seconds: 1,
        sleeper: ->(seconds) { now += seconds }
      }
    )

    watchdog.call do
      sleep 0.01 until killed
    end

    expect(Process).to have_received(:kill).with('TERM', 123)
    expect(output.string).to include('Package crawl stalled for over 10s; interrupting for resume')
  end

  it 'does not interrupt a crawl that keeps reporting progress' do
    now = 0.0
    heartbeat = PolishOpenSourceRank::Contexts::Operations::Application::ProgressHeartbeat.new(clock: -> { now })
    output = StringIO.new
    watchdog = described_class.new(
      heartbeat: heartbeat,
      output: output,
      label: 'Package crawl',
      timeout_seconds: 10,
      execution: {
        poll_seconds: 1,
        sleeper: ->(seconds) { now += seconds },
        signaler: ->(_signal) { raise 'unexpected signal' }
      }
    )

    watchdog.call do
      5.times do
        now += 5
        heartbeat.touch
      end
    end

    expect(output.string).to eq('')
  end
end
