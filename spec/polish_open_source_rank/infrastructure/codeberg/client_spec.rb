# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Infrastructure::CodebergClient do
  let(:sleeps) { [] }
  let(:sleeper) { ->(seconds) { sleeps << seconds } }
  let(:logger) { StringIO.new }
  let(:client) do
    described_class.new(token: 'token', base_url: 'https://codeberg.test/api/v1',
                        requests_per_minute: 600, execution: { sleeper: sleeper, logger: logger })
  end

  it 'performs token-authenticated JSON GET requests under the configured API base' do
    request = nil
    stub_http(ok_response({ 'ok' => true }, 'x-total-count' => '1')) { |http_request| request = http_request }

    response = client.get('/users/search', params: { q: 'Poland', page: 1 })

    expect(response.status).to eq(200)
    expect(response.body).to eq('ok' => true)
    expect(response.headers).to include('x-total-count' => '1')
    expect(request.path).to eq('/api/v1/users/search?q=Poland&page=1')
    expect(request['Authorization']).to eq('token token')
  end

  it 'raises typed errors for failed requests' do
    stub_http(response('404', 'Not Found', '{}'))
    expect { client.get('/missing') }.to raise_error(described_class::NotFound)

    stub_http(response('500', 'Server Error', 'bad'))
    expect { client.get('/bad') }.to raise_error(described_class::Error)
  end

  it 'retries retry-after responses' do
    stub_http(response('429', 'Too Many Requests', '{}', 'retry-after' => '3'), ok_response({ 'ok' => true }))

    expect(client.get('/limited').body).to eq('ok' => true)
    expect(sleeps).to include(3.0)
  end

  it 'configures explicit HTTP timeouts' do
    captured_options = nil
    client = described_class.new(
      token: 'token',
      base_url: 'https://codeberg.test/api/v1',
      requests_per_minute: 600,
      http: { open_timeout: 7, read_timeout: 31, write_timeout: 29 },
      execution: { sleeper: sleeper, logger: logger }
    )
    stub_http(ok_response({ 'ok' => true })) do |_request, options|
      captured_options = options
    end

    client.get('/users')

    expect(captured_options).to include(use_ssl: true, open_timeout: 7, read_timeout: 31, write_timeout: 29)
  end

  def stub_http(*responses)
    if block_given?
      allow(Net::HTTP).to receive(:start) do |_host, _port, **options, &net_http_block|
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request) do |request|
          yield request, options
          responses.shift
        end
        net_http_block.call(http)
      end
    else
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request).and_return(*responses)
      allow(Net::HTTP).to receive(:start).and_yield(http)
    end
  end

  def ok_response(body, headers = {})
    response('200', 'OK', JSON.generate(body), headers, Net::HTTPOK)
  end

  def response(code, message, body, headers = {}, klass = Net::HTTPResponse)
    klass.new('1.1', code, message).tap do |http_response|
      http_response.instance_variable_set(:@read, true)
      http_response.body = body
      headers.each { |key, value| http_response[key] = value }
    end
  end
end
