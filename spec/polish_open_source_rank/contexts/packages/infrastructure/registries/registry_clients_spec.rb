# frozen_string_literal: true

require 'net/http'

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Infrastructure::Registries do
  it 'fetches npm metadata and download windows with retryable rate limits' do
    stub_http(
      response('200', npm_body),
      response('429', {}, headers: { 'retry-after' => '2' }),
      response('200', { downloads: 7 }),
      response('200', { downloads: 30 })
    )

    result = client(:NpmRegistryClient, requests_per_minute: 120).fetch('@scope/tool')

    expect(result).to be_ok
    expect(result.package.to_h).to include(
      ecosystem: 'npm',
      package_name: '@scope/tool',
      repository_url: 'git+https://github.com/acme/tool.git',
      latest_version: '1.2.3'
    )
    expect(result.snapshot.to_h).to include(downloads_7d: 7, downloads_30d: 30)
    expect(request_paths).to eq(
      ['/%40scope%2Ftool', '/-/api/v1/downloads/point/last-week/%40scope%2Ftool',
       '/-/api/v1/downloads/point/last-week/%40scope%2Ftool',
       '/-/api/v1/downloads/point/last-month/%40scope%2Ftool']
    )
    expect(sleeps).to include(2.0)
  end

  it 'distinguishes not found, rate limited, and failed registry responses' do
    stub_http(response('404', {}))
    expect(client(:RubyGemsRegistryClient).fetch('missing')).to have_attributes(status: 'not_found')

    stub_http(response('429', {}, headers: { 'retry-after' => '9' }))
    result = client(:RubyGemsRegistryClient, execution: { max_retries: 0 }).fetch('limited')
    expect(result).to have_attributes(status: 'rate_limited', retry_after: 9.0)

    stub_http(response('500', {}))
    expect(client(:RubyGemsRegistryClient, execution: { max_retries: 0 }).fetch('broken')).to have_attributes(
      status: 'failed'
    )
  end

  it 'returns a partial npm package context when a download window is rate limited' do
    stub_http(
      response('200', npm_body),
      response('429', {}, headers: { 'retry-after' => '5' })
    )

    result = client(:NpmRegistryClient, execution: { max_retries: 0 }).fetch('@scope/tool')

    expect(result).to have_attributes(status: 'rate_limited', retry_after: 5.0)
    expect(result.package.to_h).to include(package_name: '@scope/tool', latest_version: '1.2.3')
  end

  it 'maps network failures to failed fetches' do
    allow(Net::HTTP).to receive(:start).and_raise(Timeout::Error, 'execution expired')

    expect(client(:RubyGemsRegistryClient).fetch('timeout')).to have_attributes(
      status: 'failed',
      error: 'execution expired'
    )
  end

  it 'maps RubyGems metadata, totals, latest version, links, and reverse dependencies' do
    stub_http(response('200', rubygems_body))

    result = client(:RubyGemsRegistryClient).fetch('polish-tool')

    expect(result.package.to_h).to include(
      ecosystem: 'rubygems',
      repository_url: 'https://github.com/acme/polish-tool',
      homepage_url: 'https://example.com/polish-tool',
      license: 'MIT',
      latest_version: '2.0.0'
    )
    expect(result.snapshot.to_h).to include(downloads_total: 12_345, dependents_count: 8)
  end

  it 'maps crates.io metadata and sends an explicit user agent' do
    stub_http(response('200', crates_body))

    result = client(:CratesRegistryClient).fetch('polish-crate')

    expect(result.package.to_h).to include(
      ecosystem: 'crates',
      repository_url: 'https://github.com/acme/polish-crate',
      license: 'MIT',
      latest_version: '0.3.0'
    )
    expect(result.snapshot.to_h).to include(downloads_total: 10_000, downloads_30d: 123)
    expect(request_headers.last['user-agent']).to eq('polish-open-source-rank')
  end

  it 'maps PyPI metadata while keeping downloads unavailable as nil' do
    stub_http(response('200', pypi_body))

    result = client(:PyPIRegistryClient).fetch('polish-python')

    expect(result.package.to_h).to include(
      ecosystem: 'pypi',
      repository_url: 'https://github.com/acme/polish-python',
      latest_version: '4.5.6'
    )
    expect(result.snapshot.to_h).to include(
      downloads_total: nil,
      downloads_30d: nil,
      metadata: { downloads_source: 'unavailable_without_bigquery' }
    )
  end

  it 'keeps missing PyPI project URLs as nil' do
    stub_http(response('200', { info: { version: '1.0.0', project_urls: {} } }))

    result = client(:PyPIRegistryClient).fetch('polish-python')

    expect(result.package.repository_url).to be_nil
  end

  it 'maps Hex, Packagist, and Go metadata using only reliable metrics' do
    stub_http(response('200', hex_body), response('200', packagist_body), response('200', go_body))

    hex = client(:HexRegistryClient).fetch('polish_hex')
    packagist = client(:PackagistRegistryClient).fetch('vendor/package')
    go = client(:GoRegistryClient).fetch('github.com/acme/tool')

    expect(hex.package.to_h).to include(ecosystem: 'hex', repository_url: 'https://github.com/acme/polish_hex')
    expect(hex.snapshot.to_h).to include(downloads_total: 500, latest_version: '1.0.0')
    expect(packagist.package.to_h).to include(
      ecosystem: 'packagist',
      repository_url: 'https://github.com/vendor/package',
      license: 'MIT',
      latest_version: '2.1.0'
    )
    expect(packagist.snapshot.downloads_total).to be_nil
    expect(go.package.to_h).to include(ecosystem: 'go', latest_version: 'v1.2.3')
    expect(go.snapshot.to_h).to include(latest_release_at: '2026-05-01T00:00:00Z', downloads_total: nil)
  end

  def client(class_name, requests_per_minute: 10_000, execution: {})
    described_class.const_get(class_name).new(
      requests_per_minute: requests_per_minute,
      execution: {
        sleeper: ->(seconds) { sleeps << seconds },
        logger: StringIO.new,
        max_retries: 2
      }.merge(execution)
    )
  end

  def stub_http(*responses)
    @responses = responses
    @request_paths = []
    @request_headers = []
    @sleeps = []
    allow(Net::HTTP).to receive(:start) do |_host, _port, **_options, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) do |request|
        request_paths << request.uri.request_uri
        request_headers << request.to_hash.transform_values(&:first)
        @responses.shift
      end
      block.call(http)
    end
  end

  def request_paths
    @request_paths ||= []
  end

  def request_headers
    @request_headers ||= []
  end

  def sleeps
    @sleeps ||= []
  end

  def response(code, body, headers: {})
    klass = code.start_with?('2') ? Net::HTTPOK : Net::HTTPResponse
    klass = Net::HTTPNotFound if code == '404'
    klass = Net::HTTPTooManyRequests if code == '429'
    Net::HTTPResponse::CODE_TO_OBJ[code] = klass
    response = klass.new('1.1', code, 'status')
    headers.each { |key, value| response[key] = value }
    response.instance_variable_set(:@read, true)
    response.body = JSON.generate(body)
    response
  end

  def npm_body
    {
      name: '@scope/tool',
      repository: { url: 'git+https://github.com/acme/tool.git' },
      license: 'MIT',
      'dist-tags': { latest: '1.2.3' }
    }
  end

  def rubygems_body
    {
      downloads: 12_345,
      version: '2.0.0',
      source_code_uri: 'https://github.com/acme/polish-tool',
      homepage_uri: 'https://example.com/polish-tool',
      licenses: ['MIT'],
      reverse_dependencies_count: 8
    }
  end

  def crates_body
    {
      crate: {
        repository: 'https://github.com/acme/polish-crate',
        homepage: 'https://example.com/crate',
        license: 'MIT',
        max_version: '0.3.0',
        downloads: 10_000,
        recent_downloads: 123
      }
    }
  end

  def pypi_body
    {
      info: {
        package_url: 'https://pypi.org/project/polish-python/',
        project_urls: { 'Source Code' => 'https://github.com/acme/polish-python' },
        version: '4.5.6'
      }
    }
  end

  def hex_body
    {
      meta: { source_url: 'https://github.com/acme/polish_hex' },
      downloads: { all: 500 },
      latest_stable_version: '1.0.0'
    }
  end

  def packagist_body
    {
      packages: {
        'vendor/package' => [
          { version: '2.1.0', source: { url: 'https://github.com/vendor/package' }, license: ['MIT'] }
        ]
      }
    }
  end

  def go_body
    { Version: 'v1.2.3', Time: '2026-05-01T00:00:00Z' }
  end
end
