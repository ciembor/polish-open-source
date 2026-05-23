# frozen_string_literal: true

require 'simplecov'

SimpleCov.start do
  enable_coverage :line
  track_files 'lib/**/*.rb'
  add_filter '/spec/'
  minimum_coverage 100
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

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.include HtmlSpecHelpers
end
