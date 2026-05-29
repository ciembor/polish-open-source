# frozen_string_literal: true

RSpec.describe File do
  let(:root) { described_class.expand_path('../..', __dir__) }

  it 'starts crawl resume without blocking the web service activation' do
    unit = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank.service'))

    expect(unit).to include(
      'ExecStartPost=-/usr/bin/systemctl start --no-block polish-open-source-rank-crawl-resume.service'
    )
  end

  it 'runs scheduled crawls as restartable locked jobs' do
    unit = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-monthly.service'))

    expect(unit).to include('Restart=on-failure')
    expect(unit).to include('TimeoutStartSec=infinity')
    expect(unit).to include('Nice=10')
    expect(unit).to include('CPUWeight=20')
    expect(unit).to include('IOWeight=20')
    expect(unit).to include('/usr/bin/flock -n /home/ciembor/polish-open-source-rank/tmp/crawl.lock')
    expect(unit).to include('--name=polish-open-source-rank-monthly')
    expect(unit).to include(
      '--memory=768m --memory-swap=768m --memory-reservation=512m --cpus=0.5 --cpu-shares=128 --pids-limit=256'
    )
  end

  it 'runs scheduled package crawls after monthly crawls with the shared database volume' do
    service = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-packages.service'))
    timer = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-packages.timer'))

    expect(service).to include(
      'After=network-online.target polish-open-source-rank-monthly.service',
      'Nice=10',
      'CPUWeight=20',
      'IOWeight=20',
      '/usr/bin/flock /home/ciembor/polish-open-source-rank/tmp/crawl.lock',
      '-v /home/ciembor/polish-open-source-rank/db:/app/db'
    )
    expect(service).to include(
      '--memory=768m --memory-swap=768m --memory-reservation=512m --cpus=0.5 --cpu-shares=128 --pids-limit=256'
    )
    expect(service).to include('bundle exec ruby bin/package_rankings --require-monthly-complete')
    expect(service).to include(
      '--repository-limit all --scan-limit all --manifest-limit all --registry-limit all'
    )
    expect(timer).to include('OnCalendar=*-*-02 07:15:00')
    expect(timer).to include('Persistent=true')
  end

  it 'runs manual crawls with persisted arguments and restart policy' do
    unit = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-crawl.service'))

    expect(unit).to include('EnvironmentFile=-/home/ciembor/polish-open-source-rank/.crawl.env')
    expect(unit).to include('-e CRAWL_ARGS')
    expect(unit).to include('Restart=on-failure')
    expect(unit).to include('TimeoutStartSec=infinity')
    expect(unit).to include('Nice=10')
    expect(unit).to include('CPUWeight=20')
    expect(unit).to include('IOWeight=20')
    expect(unit).to include(
      '--memory=768m --memory-swap=768m --memory-reservation=512m --cpus=0.5 --cpu-shares=128 --pids-limit=256'
    )
  end

  it 'runs crawl resume with bounded container resources' do
    unit = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-crawl-resume.service'))

    expect(unit).to include('bundle exec ruby bin/resume_crawls')
    expect(unit).to include('Nice=10')
    expect(unit).to include('CPUWeight=20')
    expect(unit).to include('IOWeight=20')
    expect(unit).to include(
      '--memory=768m --memory-swap=768m --memory-reservation=512m --cpus=0.5 --cpu-shares=128 --pids-limit=256'
    )
  end
end
