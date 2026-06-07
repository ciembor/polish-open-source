# frozen_string_literal: true

RSpec.describe File do
  let(:root) { described_class.expand_path('../..', __dir__) }

  it 'starts crawl resume without blocking the web service activation' do
    unit = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank.service'))

    expect(unit).to include(
      'ExecStartPost=-/usr/bin/systemctl start --no-block polish-open-source-rank-crawl-resume.service',
      '--user=1000:1000 --read-only --tmpfs /app/tmp:rw,noexec,nosuid,nodev,size=64m',
      '-e GOOGLE_ANALYTICS_MEASUREMENT_ID=G-QHRZZZLKPE',
      '-v /home/ciembor/polish-open-source-rank/db:/app/db:rw',
      '-v /home/ciembor/polish-open-source-rank/log:/app/log:rw'
    )
  end

  it 'runs scheduled crawls as restartable locked jobs' do
    unit = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-monthly.service'))
    timer = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-monthly.timer'))

    expect(unit).to include(
      'Restart=on-failure',
      'TimeoutStartSec=infinity',
      'Nice=10',
      'CPUWeight=20',
      'IOWeight=20',
      '/usr/bin/flock -n /home/ciembor/polish-open-source-rank/tmp/crawl.lock',
      '--name=polish-open-source-rank-monthly',
      'bundle exec ruby bin/monthly_rankings',
      '--user=1000:1000 --read-only --tmpfs /app/tmp:rw,noexec,nosuid,nodev,size=64m'
    )
    expect(unit).not_to include('--use-stars-diff')
    expect(unit).to include(
      '--memory=768m --memory-swap=768m --memory-reservation=512m --cpus=0.5 --cpu-shares=128 --pids-limit=256'
    )
    expect(timer).to include('OnCalendar=*-*-01 00:00:00')
    expect(timer).to include('Persistent=true')
  end

  it 'runs scheduled package crawls after monthly crawls with the shared database volume' do
    service = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-packages.service'))
    timer = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-packages.timer'))

    expect(service).to include(
      'After=network-online.target polish-open-source-rank-monthly.service',
      'OnSuccess=polish-open-source-rank-publish.service',
      'Nice=10',
      'CPUWeight=20',
      'IOWeight=20',
      '/usr/bin/flock /home/ciembor/polish-open-source-rank/tmp/packages.lock',
      '--user=1000:1000 --read-only --tmpfs /app/tmp:rw,noexec,nosuid,nodev,size=64m',
      '-v /home/ciembor/polish-open-source-rank/db:/app/db:rw'
    )
    expect(service).to include(
      '--memory=768m --memory-swap=768m --memory-reservation=512m --cpus=0.5 --cpu-shares=128 --pids-limit=256'
    )
    expect(service).to include('bundle exec ruby bin/package_rankings --require-monthly-complete')
    expect(service).to include(
      '--repository-limit all --scan-limit all --manifest-limit all --registry-limit all'
    )
    expect(timer).to include('OnCalendar=*-*-01 00:00:00')
    expect(timer).to include('Persistent=true')
  end

  it 'publishes the public snapshot after successful package crawls' do
    service = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-publish.service'))
    deploy = described_class.read(described_class.join(root, 'scripts/deploy.sh'))

    expect(service).to include(
      'After=network-online.target polish-open-source-rank-packages.service',
      'Restart=on-failure',
      'RestartSec=300',
      '--name=polish-open-source-rank-publish',
      '--user=1000:1000 --read-only --tmpfs /app/tmp:rw,noexec,nosuid,nodev,size=64m',
      '-v /home/ciembor/polish-open-source-rank/db:/app/db:rw',
      'bundle exec ruby bin/publish_snapshot'
    )
    expect(deploy).to include('"${SERVICE_NAME}-publish.service"')
  end

  it 'runs manual crawls with persisted arguments and restart policy' do
    unit = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-crawl.service'))

    expect(unit).to include('EnvironmentFile=-/home/ciembor/polish-open-source-rank/.crawl.env')
    expect(unit).to include('-e CRAWL_ARGS')
    expect(unit).to include('bundle exec ruby bin/monthly_rankings ${CRAWL_ARGS:-}')
    expect(unit).not_to include('--use-stars-diff')
    expect(unit).to include('Restart=on-failure')
    expect(unit).to include('TimeoutStartSec=infinity')
    expect(unit).to include('Nice=10')
    expect(unit).to include('CPUWeight=20')
    expect(unit).to include('IOWeight=20')
    expect(unit).to include(
      '--user=1000:1000 --read-only --tmpfs /app/tmp:rw,noexec,nosuid,nodev,size=64m',
      '--memory=768m --memory-swap=768m --memory-reservation=512m --cpus=0.5 --cpu-shares=128 --pids-limit=256'
    )
  end

  it 'runs production alerts on a dedicated timer with the app env file and host sandboxing' do
    service = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-alerts.service'))
    timer = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-alerts.timer'))

    expect(service).to include(
      'EnvironmentFile=-/home/ciembor/polish-open-source-rank/.env.local',
      'NoNewPrivileges=true',
      'ProtectSystem=strict',
      'ReadWritePaths=/home/ciembor/polish-open-source-rank/tmp /home/ciembor/polish-open-source-rank/log',
      'ExecStart=/usr/bin/python3 /home/ciembor/polish-open-source-rank/scripts/production_alert_monitor.py'
    )
    expect(timer).to include('OnUnitActiveSec=1min', 'Persistent=true')
  end

  it 'runs the host monitor with host sandboxing while keeping the log writable' do
    service = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-monitor.service'))

    expect(service).to include(
      'NoNewPrivileges=true',
      'ProtectSystem=strict',
      'ProtectHome=read-only',
      'ReadWritePaths=/home/ciembor/polish-open-source-rank/log'
    )
  end

  it 'runs crawl resume with bounded container resources' do
    unit = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-crawl-resume.service'))

    expect(unit).to include('bundle exec ruby bin/resume_crawls')
    expect(unit).to include('SuccessExitStatus=75')
    expect(unit).to include('/usr/bin/flock -n -E 75 /home/ciembor/polish-open-source-rank/tmp/crawl.lock')
    expect(unit).to include('Nice=10')
    expect(unit).to include('CPUWeight=20')
    expect(unit).to include('IOWeight=20')
    expect(unit).to include(
      '--user=1000:1000 --read-only --tmpfs /app/tmp:rw,noexec,nosuid,nodev,size=64m',
      '--memory=768m --memory-swap=768m --memory-reservation=512m --cpus=0.5 --cpu-shares=128 --pids-limit=256'
    )
  end
end
