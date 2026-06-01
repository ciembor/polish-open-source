#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'optparse'
require 'securerandom'
require 'time'
require 'uri'

Endpoint = Struct.new(:name, :path, :weight, keyword_init: true)
Sample = Struct.new(:endpoint, :status, :duration_ms, :bytes, keyword_init: true)

DEFAULT_ENDPOINTS = [
  Endpoint.new(name: 'latest', path: '/latest', weight: 16),
  Endpoint.new(name: 'ranking_users', path: '/latest/users/top', weight: 8),
  Endpoint.new(name: 'ranking_repositories', path: '/latest/repositories/top', weight: 8),
  Endpoint.new(name: 'organizations', path: '/latest/organizations', weight: 8),
  Endpoint.new(name: 'profile', path: '/users/github/alice', weight: 8),
  Endpoint.new(name: 'languages', path: '/languages', weight: 8),
  Endpoint.new(name: 'language_detail', path: '/languages/ruby', weight: 4),
  Endpoint.new(name: 'packages', path: '/packages', weight: 8),
  Endpoint.new(name: 'package_detail', path: '/packages/npm', weight: 4),
  Endpoint.new(name: 'badge', path: '/badges/users/github/alice.svg', weight: 2)
].freeze

options = {
  base_url: ENV.fetch('BASE_URL', 'http://localhost:9292'),
  concurrency: Integer(ENV.fetch('CONCURRENCY', '4')),
  duration: Integer(ENV.fetch('DURATION', '30')),
  slo_p95: Float(ENV.fetch('SLO_P95_MS', '500')),
  slo_p99: Float(ENV.fetch('SLO_P99_MS', '1500')),
  max_5xx_rate: Float(ENV.fetch('MAX_5XX_RATE', '0.001')),
  accept_language: ENV.fetch('ACCEPT_LANGUAGE', 'pl')
}

OptionParser.new do |parser|
  parser.banner = 'Usage: scripts/public_load_test.rb [options]'
  parser.on('--base-url URL', 'Base URL, default BASE_URL or http://localhost:9292') { |value| options[:base_url] = value }
  parser.on('--concurrency N', Integer, 'Worker count, default 4') { |value| options[:concurrency] = value }
  parser.on('--duration SECONDS', Integer, 'Run duration, default 30') { |value| options[:duration] = value }
  parser.on('--slo-p95 MS', Float, 'p95 latency budget, default 500') { |value| options[:slo_p95] = value }
  parser.on('--slo-p99 MS', Float, 'p99 latency budget, default 1500') { |value| options[:slo_p99] = value }
  parser.on('--max-5xx-rate RATE', Float, '5xx budget, default 0.001') { |value| options[:max_5xx_rate] = value }
end.parse!

deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + options.fetch(:duration)
samples = Queue.new
weighted_paths = DEFAULT_ENDPOINTS.flat_map { |endpoint| [endpoint] * endpoint.weight }

def perform_request(uri, endpoint, options, samples)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    request = Net::HTTP::Get.new(uri)
    request['Accept-Language'] = options.fetch(:accept_language)
    request['User-Agent'] = 'polish-open-source-rank-load-test/1.0'
    http.request(request)
  end
  elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
  samples << Sample.new(
    endpoint: endpoint.name,
    status: response.code.to_i,
    duration_ms: elapsed_ms,
    bytes: response.body.to_s.bytesize
  )
rescue StandardError
  elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
  samples << Sample.new(endpoint: endpoint.name, status: 599, duration_ms: elapsed_ms, bytes: 0)
end

workers = options.fetch(:concurrency).times.map do
  Thread.new do
    uri_base = URI(options.fetch(:base_url))
    rng = Random.new(SecureRandom.random_number(1 << 31))

    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      endpoint = weighted_paths.fetch(rng.rand(weighted_paths.length))
      perform_request(uri_base + endpoint.path, endpoint, options, samples)
    end
  end
end

workers.each(&:join)
results = []
results << samples.pop until samples.empty?

def percentile(values, percentile)
  return 0.0 if values.empty?

  sorted = values.sort
  sorted[((sorted.length - 1) * percentile).ceil]
end

latencies = results.map(&:duration_ms)
statuses = results.group_by(&:status).transform_values(&:length)
by_endpoint = results.group_by(&:endpoint).transform_values do |endpoint_samples|
  endpoint_latencies = endpoint_samples.map(&:duration_ms)
  {
    count: endpoint_samples.length,
    p95_ms: percentile(endpoint_latencies, 0.95).round(1),
    p99_ms: percentile(endpoint_latencies, 0.99).round(1),
    statuses: endpoint_samples.group_by(&:status).transform_values(&:length)
  }
end

total = results.length
server_errors = results.count { |sample| sample.status >= 500 }
rate_limited = results.count { |sample| sample.status == 429 }
p95 = percentile(latencies, 0.95)
p99 = percentile(latencies, 0.99)
failed_slo = p95 > options.fetch(:slo_p95) ||
             p99 > options.fetch(:slo_p99) ||
             (total.positive? && server_errors.fdiv(total) > options.fetch(:max_5xx_rate)) ||
             rate_limited.positive?

report = {
  base_url: options.fetch(:base_url),
  duration_seconds: options.fetch(:duration),
  concurrency: options.fetch(:concurrency),
  requests: total,
  requests_per_second: total.fdiv(options.fetch(:duration)).round(2),
  p95_ms: p95.round(1),
  p99_ms: p99.round(1),
  server_error_rate: (total.zero? ? 0 : server_errors.fdiv(total)).round(5),
  rate_limited_responses: rate_limited,
  statuses: statuses,
  by_endpoint: by_endpoint,
  slo: {
    p95_ms: options.fetch(:slo_p95),
    p99_ms: options.fetch(:slo_p99),
    max_5xx_rate: options.fetch(:max_5xx_rate),
    passed: !failed_slo
  }
}

puts JSON.pretty_generate(report)
exit(failed_slo ? 1 : 0)
