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
    expect(unit).to include('/usr/bin/flock -n /home/ciembor/polish-open-source-rank/tmp/crawl.lock')
    expect(unit).to include('--name=polish-open-source-rank-monthly')
  end

  it 'runs manual crawls with persisted arguments and restart policy' do
    unit = described_class.read(described_class.join(root, 'deploy/polish-open-source-rank-crawl.service'))

    expect(unit).to include('EnvironmentFile=-/home/ciembor/polish-open-source-rank/.crawl.env')
    expect(unit).to include('-e CRAWL_ARGS')
    expect(unit).to include('Restart=on-failure')
    expect(unit).to include('TimeoutStartSec=infinity')
  end
end
