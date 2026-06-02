# frozen_string_literal: true

RSpec.describe File do
  let(:root) { described_class.expand_path('../..', __dir__) }

  it 'proxies internal production routes without owning application authentication' do
    snippet = described_class.read(
      described_class.join(root, 'deploy/nginx-polish-open-source-rank-internal.conf')
    )

    expect(snippet).to include(
      'location ^~ /internal/',
      'proxy_pass http://127.0.0.1:9293;',
      'proxy_set_header X-Real-IP $remote_addr;',
      'proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;'
    )
    expect(snippet).not_to include('auth_basic')
  end
end
