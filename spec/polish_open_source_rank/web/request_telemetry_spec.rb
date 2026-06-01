# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::RequestTelemetry do
  it 'adds a request id and logs structured request telemetry' do
    output = StringIO.new
    now = 10.0
    app = ->(_env) { [200, { 'Cache-Control' => 'public, max-age=60' }, ['ok']] }
    middleware = described_class.new(app, logger: output, clock: -> { now += 0.0123 })

    status, headers, = middleware.call(
      'PATH_INFO' => '/latest/users/top',
      'REQUEST_METHOD' => 'GET',
      'HTTP_X_REQUEST_ID' => 'request-1'
    )
    payload = JSON.parse(output.string)

    expect(status).to eq(200)
    expect(headers['X-Request-Id']).to eq('request-1')
    expect(payload).to include(
      'event' => 'http_request',
      'request_id' => 'request-1',
      'method' => 'GET',
      'path_template' => '/:period/:scope/:kind/:metric',
      'status' => 200,
      'cache' => 'miss'
    )
    expect(payload.fetch('latency_ms')).to be > 0
  end

  it 'logs cache hits for conditional responses' do
    output = StringIO.new
    app = ->(_env) { [304, {}, []] }
    middleware = described_class.new(app, logger: output, clock: -> { 1.0 })

    middleware.call('PATH_INFO' => '/badges/users/github/alice.svg', 'REQUEST_METHOD' => 'GET')

    expect(JSON.parse(output.string)).to include(
      'path_template' => '/badges/:kind',
      'status' => 304,
      'cache' => 'hit'
    )
  end

  it 'logs and reraises request errors' do
    output = StringIO.new
    app = ->(_env) { raise 'boom' }
    middleware = described_class.new(app, logger: output, clock: -> { 1.0 })

    expect do
      middleware.call('PATH_INFO' => '/auth/github', 'REQUEST_METHOD' => 'GET')
    end.to raise_error(RuntimeError, 'boom')

    expect(JSON.parse(output.string)).to include(
      'path_template' => '/auth/:provider',
      'status' => 500,
      'cache' => 'none',
      'error_class' => 'RuntimeError'
    )
  end
end
