# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::RateLimiter do
  it 'passes requests without a matching rule' do
    app = ->(_env) { [200, {}, ['ok']] }
    limiter = described_class.new(app)

    status, = limiter.call('PATH_INFO' => '/people', 'REMOTE_ADDR' => '127.0.0.1')

    expect(status).to eq(200)
  end

  it 'limits matching paths per forwarded client address and can reset the store', :aggregate_failures do
    rule = described_class::Rule.new(name: 'test', limit: 1, window: 60)
    store = described_class::Store.new(clock: -> { 10.0 })
    app = ->(_env) { [200, {}, ['ok']] }
    limiter = described_class.new(app, store: store, rules: { %r{\A/limited} => rule })
    env = {
      'PATH_INFO' => '/limited',
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_X_FORWARDED_FOR' => '203.0.113.9, 127.0.0.1'
    }

    first_status, = limiter.call(env)
    limited_status, limited_headers, limited_body = limiter.call(env)
    store.reset
    reset_status, = limiter.call(env)

    expect(first_status).to eq(200)
    expect(limited_status).to eq(429)
    expect(limited_headers).to include(
      'Cache-Control' => 'no-store',
      'RateLimit-Limit' => '1',
      'RateLimit-Remaining' => '0'
    )
    expect(limited_headers['Retry-After']).to match(/\A\d+\z/)
    expect(limited_body.join).to eq("Too many requests\n")
    expect(reset_status).to eq(200)
  end

  it 'ignores spoofed forwarded headers when the request is not from a trusted proxy' do
    rule = described_class::Rule.new(name: 'test', limit: 1, window: 60)
    store = described_class::Store.new(clock: -> { 10.0 })
    app = ->(_env) { [200, {}, ['ok']] }
    limiter = described_class.new(app, store: store, rules: { %r{\A/limited} => rule })

    first_status, = limiter.call(
      'PATH_INFO' => '/limited',
      'REMOTE_ADDR' => '198.51.100.10',
      'HTTP_X_FORWARDED_FOR' => '203.0.113.1'
    )
    limited_status, = limiter.call(
      'PATH_INFO' => '/limited',
      'REMOTE_ADDR' => '198.51.100.10',
      'HTTP_X_FORWARDED_FOR' => '203.0.113.2'
    )

    expect(first_status).to eq(200)
    expect(limited_status).to eq(429)
  end

  it 'uses proxy-controlled real client addresses from trusted proxies' do
    rule = described_class::Rule.new(name: 'test', limit: 1, window: 60)
    store = described_class::Store.new(clock: -> { 10.0 })
    app = ->(_env) { [200, {}, ['ok']] }
    limiter = described_class.new(app, store: store, rules: { %r{\A/limited} => rule })

    first_status, = limiter.call(
      'PATH_INFO' => '/limited',
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_X_REAL_IP' => '203.0.113.10'
    )
    other_status, = limiter.call(
      'PATH_INFO' => '/limited',
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_X_REAL_IP' => '203.0.113.11'
    )
    limited_status, = limiter.call(
      'PATH_INFO' => '/limited',
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_X_REAL_IP' => '203.0.113.10'
    )

    expect(first_status).to eq(200)
    expect(other_status).to eq(200)
    expect(limited_status).to eq(429)
  end

  it 'falls back to the proxy address when every forwarded address is trusted or invalid' do
    rule = described_class::Rule.new(name: 'test', limit: 1, window: 60)
    store = described_class::Store.new(clock: -> { 10.0 })
    app = ->(_env) { [200, {}, ['ok']] }
    limiter = described_class.new(app, store: store, rules: { %r{\A/limited} => rule })
    env = {
      'PATH_INFO' => '/limited',
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_X_REAL_IP' => 'not-an-ip',
      'HTTP_X_FORWARDED_FOR' => 'also-not-an-ip, 10.0.0.2'
    }

    first_status, = limiter.call(env)
    limited_status, = limiter.call(env)

    expect(first_status).to eq(200)
    expect(limited_status).to eq(429)
  end

  it 'opens a new bucket after the window expires' do
    now = 0.0
    clock = -> { now }
    rule = described_class::Rule.new(name: 'test', limit: 1, window: 1)
    store = described_class::Store.new(clock: clock)

    first = store.check('key', rule)
    second = store.check('key', rule)
    now = 2.0
    third = store.check('key', rule)

    expect(first).to be_allowed
    expect(second).not_to be_allowed
    expect(third).to be_allowed
  end
end
