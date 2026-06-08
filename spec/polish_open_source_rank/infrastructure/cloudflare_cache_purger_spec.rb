# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Infrastructure::CloudflareCachePurger do
  it 'purges the whole Cloudflare zone with configured credentials and timeouts' do
    logger = StringIO.new
    captured_request = nil
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request) do |request|
      captured_request = request
      response('200', 'OK', JSON.generate('success' => true), Net::HTTPOK)
    end
    allow(Net::HTTP).to receive(:start).and_yield(http)

    purger = described_class.new(
      zone_id: 'zone-id',
      api_token: 'api-token',
      timeouts: { open_timeout: 2, read_timeout: 8, write_timeout: 9 },
      logger: logger
    )

    expect(purger.purge_public_cache).to be(true)

    expect(Net::HTTP).to have_received(:start).with(
      'api.cloudflare.com',
      443,
      use_ssl: true,
      open_timeout: 2,
      read_timeout: 8,
      write_timeout: 9
    )
    expect(captured_request).to be_a(Net::HTTP::Post)
    expect(captured_request.path).to eq('/client/v4/zones/zone-id/purge_cache')
    expect(captured_request['Authorization']).to eq('Bearer api-token')
    expect(captured_request['Content-Type']).to eq('application/json')
    expect(JSON.parse(captured_request.body)).to eq('purge_everything' => true)
    expect(logger.string).to be_empty
  end

  it 'logs Cloudflare failures without raising' do
    logger = StringIO.new
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request).and_return(
      response('400', 'Bad Request', JSON.generate('success' => false), Net::HTTPBadRequest)
    )
    allow(Net::HTTP).to receive(:start).and_yield(http)

    purger = described_class.new(
      zone_id: 'zone-id',
      api_token: 'api-token',
      timeouts: { open_timeout: 2, read_timeout: 8, write_timeout: 9 },
      logger: logger
    )

    expect(purger.purge_public_cache).to be(false)
    expect(logger.string).to include('Cloudflare cache purge failed: HTTP 400')
  end

  it 'logs unsuccessful Cloudflare JSON responses' do
    logger = StringIO.new
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request).and_return(
      response('200', 'OK', JSON.generate('success' => false), Net::HTTPOK)
    )
    allow(Net::HTTP).to receive(:start).and_yield(http)

    purger = described_class.new(
      zone_id: 'zone-id',
      api_token: 'api-token',
      timeouts: { open_timeout: 2, read_timeout: 8, write_timeout: 9 },
      logger: logger
    )

    expect(purger.purge_public_cache).to be(false)
    expect(logger.string).to include('Cloudflare cache purge failed: {"success":false}')
  end

  it 'accepts successful non-JSON Cloudflare responses' do
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request).and_return(response('200', 'OK', '', Net::HTTPOK))
    allow(Net::HTTP).to receive(:start).and_yield(http)

    purger = described_class.new(
      zone_id: 'zone-id',
      api_token: 'api-token',
      timeouts: { open_timeout: 2, read_timeout: 8, write_timeout: 9 },
      logger: StringIO.new
    )

    expect(purger.purge_public_cache).to be(true)
  end

  it 'logs network failures without raising' do
    logger = StringIO.new
    allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout, 'execution expired')

    purger = described_class.new(
      zone_id: 'zone-id',
      api_token: 'api-token',
      timeouts: { open_timeout: 2, read_timeout: 8, write_timeout: 9 },
      logger: logger
    )

    expect(purger.purge_public_cache).to be(false)
    expect(logger.string).to include('Cloudflare cache purge failed: Net::OpenTimeout')
  end

  it 'builds a configured purger from complete Cloudflare credentials' do
    configuration = instance_double(
      PolishOpenSourceRank::Configuration,
      cloudflare_zone_id: 'zone-id',
      cloudflare_api_token: 'api-token',
      user_action_http_timeouts: { open_timeout: 2, read_timeout: 8, write_timeout: 9 }
    )

    purger = described_class.from_configuration(configuration, logger: StringIO.new)

    expect(purger).to be_a(described_class)
  end

  it 'builds a no-op purger when Cloudflare credentials are incomplete' do
    logger = StringIO.new
    configuration = instance_double(
      PolishOpenSourceRank::Configuration,
      cloudflare_zone_id: 'zone-id',
      cloudflare_api_token: nil
    )

    purger = described_class.from_configuration(configuration, logger: logger)

    expect(purger.purge_public_cache).to be_nil
    expect(logger.string).to include('Cloudflare cache purge skipped')
  end

  def response(code, message, body, klass)
    klass.new('1.1', code, message).tap do |http_response|
      http_response.instance_variable_set(:@read, true)
      http_response.body = body
    end
  end
end
