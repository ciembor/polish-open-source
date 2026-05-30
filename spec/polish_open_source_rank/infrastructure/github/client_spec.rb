# frozen_string_literal: true

require 'net/http'

RSpec.describe PolishOpenSourceRank::Infrastructure::GitHubClient do
  let(:sleeps) { [] }
  let(:sleeper) { ->(seconds) { sleeps << seconds } }
  let(:client) do
    described_class.new(
      token: 'token',
      requests_per_minute: 600,
      execution: { sleeper: sleeper, logger: StringIO.new }
    )
  end

  it 'performs authenticated JSON GET requests' do
    stub_http(ok_response({ 'ok' => true }, 'x-ratelimit-remaining' => '1'))

    response = client.get('/user', params: { page: 1 })

    expect(response.status).to eq(200)
    expect(response.body).to eq('ok' => true)
    expect(response.headers).to include('x-ratelimit-remaining' => '1')
  end

  it 'sleeps before consuming the final primary rate limit request' do
    stub_http(ok_response({}, 'x-ratelimit-remaining' => '1', 'x-ratelimit-reset' => Time.now.to_i.to_s))

    client.get('/rate-limited')

    expect(sleeps).to include(1)
  end

  it 'retries retry-after responses' do
    stub_http(
      response('429', 'Too Many Requests', '{}', 'retry-after' => '2'),
      ok_response({ 'ok' => true }, 'x-ratelimit-remaining' => '1')
    )

    expect(client.get('/retry').body).to eq('ok' => true)
    expect(sleeps).to include(2.0)
  end

  it 'retries primary rate limit responses until reset' do
    stub_http(
      response('403', 'Forbidden', '{}', 'x-ratelimit-remaining' => '0', 'x-ratelimit-reset' => Time.now.to_i.to_s),
      ok_response({ 'ok' => true }, 'x-ratelimit-remaining' => '1')
    )

    expect(client.get('/reset').body).to eq('ok' => true)
    expect(sleeps).to include(1)
  end

  it 'does not retry generic forbidden responses' do
    stub_http(response('403', 'Forbidden', '{"message":"Repository access blocked"}'))

    expect { client.get('/blocked') }.to raise_error(described_class::Error)
    expect(sleeps).to be_empty
    expect(Net::HTTP).to have_received(:start).once
  end

  it 'uses exponential backoff for server errors without retry headers' do
    stub_http(
      response('500', 'Server Error', '{}'),
      ok_response({ 'ok' => true }, 'x-ratelimit-remaining' => '1')
    )

    expect(client.get('/flaky').body).to eq('ok' => true)
    expect(sleeps.any? { |seconds| seconds.between?(2, 3) }).to be(true)
  end

  it 'retries public organization policy failures without the token' do
    authorizations = []
    policy_error = JSON.generate(
      'message' => 'The organization forbids access via a fine-grained personal access tokens'
    )
    stub_http(
      response('403', 'Forbidden', policy_error),
      ok_response({ 'login' => 'blocked-org' }, 'x-ratelimit-remaining' => '59')
    ) do |request, _options|
      authorizations << request['Authorization']
    end

    response = client.get('/orgs/blocked-org')

    expect(response.body).to eq('login' => 'blocked-org')
    expect(authorizations).to eq(['Bearer token', nil])
  end

  it 'follows repository redirects and returns the redirected response body' do
    stub_http(
      response('301', 'Moved Permanently', '', 'location' => 'https://api.github.com/repos/QuestPDF/QuestPDF'),
      ok_response({ 'full_name' => 'QuestPDF/QuestPDF' }, 'x-ratelimit-remaining' => '59')
    )

    response = client.get('/repos/QuestPDF/QuestPDF.Native')

    expect(response.body).to eq('full_name' => 'QuestPDF/QuestPDF')
  end

  it 'raises an HTTP error when a redirect location is invalid' do
    stub_http(response('301', 'Moved Permanently', '', 'location' => '://bad redirect'))

    expect { client.get('/repos/QuestPDF/QuestPDF.Native') }.to raise_error(described_class::Error)
  end

  it 'retries transient transport errors' do
    stub_http_start(
      Net::OpenTimeout.new('execution expired'),
      ok_response({ 'ok' => true }, 'x-ratelimit-remaining' => '1')
    )

    expect(client.get('/flaky-network').body).to eq('ok' => true)
    expect(sleeps.any? { |seconds| seconds.between?(2, 3) }).to be(true)
  end

  it 'raises transport errors after exhausting retries' do
    client = described_class.new(
      token: 'token',
      requests_per_minute: 600,
      execution: { sleeper: sleeper, logger: StringIO.new, max_retries: 1 }
    )
    stub_http_start(
      OpenSSL::SSL::SSLError.new('unexpected eof while reading'),
      OpenSSL::SSL::SSLError.new('unexpected eof while reading')
    )

    expect { client.get('/broken-network') }.to raise_error(OpenSSL::SSL::SSLError)
    expect(Net::HTTP).to have_received(:start).twice
  end

  it 'raises typed errors for unretryable statuses and missing resources' do
    stub_http(response('404', 'Not Found', '{}'))
    expect { client.get('/missing') }.to raise_error(described_class::NotFound)

    stub_http(response('400', 'Bad Request', 'bad'))
    expect { client.get('/bad') }.to raise_error(described_class::Error)
  end

  it 'configures explicit HTTP timeouts' do
    captured_options = nil
    client = described_class.new(
      token: 'token',
      requests_per_minute: 600,
      http: { open_timeout: 7, read_timeout: 31, write_timeout: 29 },
      execution: { sleeper: sleeper, logger: StringIO.new }
    )
    stub_http(ok_response({ 'ok' => true }, 'x-ratelimit-remaining' => '1')) do |_request, options|
      captured_options = options
    end

    client.get('/timeouts')

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

  def stub_http_start(*steps)
    allow(Net::HTTP).to receive(:start) do |_host, _port, **_options, &net_http_block|
      step = steps.shift
      raise step if step.is_a?(Exception)

      http = instance_double(Net::HTTP)
      allow(http).to receive(:request).and_return(step)
      net_http_block.call(http)
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
