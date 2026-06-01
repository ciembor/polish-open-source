# frozen_string_literal: true

require 'simplecov'

ENV['RACK_ENV'] ||= 'test'

simplecov_command_name = ENV.fetch('SIMPLECOV_COMMAND_NAME', nil)
if simplecov_command_name
  SimpleCov.command_name(simplecov_command_name)
  SimpleCov.coverage_dir("coverage/#{simplecov_command_name}")
end

SimpleCov.start do
  enable_coverage :line
  track_files 'lib/**/*.rb'
  add_filter '/spec/'
  minimum_coverage 100 unless ENV['SIMPLECOV_SKIP_MINIMUM_COVERAGE'] == 'true'
end

if ENV['KNAPSACK'] == 'true'
  require 'knapsack'

  Knapsack.tracker.config(
    enable_time_offset_warning: true,
    time_offset_in_seconds: 10
  )
  Knapsack.report.config(
    report_path: ENV.fetch('KNAPSACK_REPORT_PATH', 'knapsack_rspec_report.json')
  )
  Knapsack::Adapters::RSpecAdapter.bind
end

require 'rack/mock'
require 'rexml/document'
require 'rspec'
require 'stringio'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'polish_open_source_rank'

module HtmlSpecHelpers
  VOID_ELEMENTS = %w[area base br col embed hr img input link meta param source track wbr].freeze
  BOOLEAN_ATTRIBUTES = %w[async checked defer disabled hidden multiple readonly required selected].freeze

  def html_document(body)
    REXML::Document.new(xml_compatible_html(body))
  end

  def xml_document(body)
    REXML::Document.new(body)
  end

  def html_elements(body, xpath)
    REXML::XPath.match(html_document(body), xpath)
  end

  def html_element(body, xpath)
    REXML::XPath.first(html_document(body), xpath)
  end

  private

  def xml_compatible_html(body)
    html = body.sub(/\A<!doctype html>\s*/i, '')
    html = html.gsub(/<[^>]+>/) { |tag| normalize_boolean_attributes(tag) }

    VOID_ELEMENTS.reduce(html) do |markup, tag|
      markup.gsub(/<#{tag}\b([^>]*)>/i) do |match|
        match.end_with?('/>') ? match : "<#{tag}#{::Regexp.last_match(1)} />"
      end
    end
  end

  def normalize_boolean_attributes(tag)
    BOOLEAN_ATTRIBUTES.reduce(tag) do |markup, attribute|
      markup.gsub(%r{(\s)#{attribute}(?=[\s>/])}i, "\\1#{attribute}=\"#{attribute}\"")
    end
  end
end

module FixtureSpecHelpers
  def fixture_json(relative_path)
    JSON.parse(File.read(File.expand_path("fixtures/#{relative_path}", __dir__)))
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.include HtmlSpecHelpers
  config.include FixtureSpecHelpers
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.include HtmlSpecHelpers
  config.include FixtureSpecHelpers

  config.after do
    ObjectSpace.each_object(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database, &:close)
  end
end
