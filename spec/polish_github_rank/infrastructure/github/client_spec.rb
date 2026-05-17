# frozen_string_literal: true

require 'net/http'

RSpec.describe PolishGithubRank::Infrastructure::GitHubClient do
  let(:sleeps) { [] }
  let(:sleeper) { ->(seconds) { sleeps << seconds } }
  let(:client) { described_class.new(token: 'token', requests_per_minute: 600, sleeper: sleeper, logger: StringIO.new) }

  it 'performs authenticated JSON GET requests' do
    stub_http(ok_response({ 'ok' => true }, 'x-ratelimit-remaining' => '1'))

    response = client.get('/user', params: { page: 1 })

    expect(response.status).to eq(200)
    expect(response.body).to eq('ok' => true)
    expect(response.headers).to include('x-ratelimit-remaining' => '1')
  end

  it 'sleeps when a successful response exhausts the primary rate limit' do
    stub_http(ok_response({}, 'x-ratelimit-remaining' => '0', 'x-ratelimit-reset' => Time.now.to_i.to_s))

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

  it 'uses exponential backoff for server errors without retry headers' do
    stub_http(
      response('500', 'Server Error', '{}'),
      ok_response({ 'ok' => true }, 'x-ratelimit-remaining' => '1')
    )

    expect(client.get('/flaky').body).to eq('ok' => true)
    expect(sleeps.any? { |seconds| seconds.between?(2, 3) }).to be(true)
  end

  it 'raises typed errors for unretryable statuses and missing resources' do
    stub_http(response('404', 'Not Found', '{}'))
    expect { client.get('/missing') }.to raise_error(described_class::NotFound)

    stub_http(response('400', 'Bad Request', 'bad'))
    expect { client.get('/bad') }.to raise_error(described_class::Error)
  end

  def stub_http(*responses)
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request).and_return(*responses)
    allow(Net::HTTP).to receive(:start).and_yield(http)
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
