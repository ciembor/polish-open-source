# frozen_string_literal: true

require 'simplecov'

SimpleCov.start do
  enable_coverage :line
  track_files 'lib/**/*.rb'
  add_filter '/spec/'
  minimum_coverage 100
end

require 'rack/mock'
require 'rspec'
require 'stringio'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'polish_open_source_rank'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
end
