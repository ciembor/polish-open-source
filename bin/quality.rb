#!/usr/bin/env ruby
# frozen_string_literal: true

require 'English'
require 'fileutils'
require 'shellwords'

BIN_DIR = __dir__

def run_command(env, command)
  env_label = env.map { |key, value| "#{key}=#{value}" }.join(' ')
  prefix = env_label.empty? ? '$' : "$ #{env_label}"
  puts "#{prefix} #{command.join(' ')}"
  system(env, *command) || exit($CHILD_STATUS.exitstatus || 1)
end

commands = [
  [File.join(BIN_DIR, 'bundle'), 'exec', 'rubocop', '--cache-root', 'tmp/rubocop_cache'],
  [File.join(BIN_DIR, 'bundle'), 'exec', 'reek'],
  [File.join(BIN_DIR, 'bundle'), 'exec', 'bundle-audit', 'check']
]

commands.each { |command| run_command({}, command) }

node_total = ENV.fetch('KNAPSACK_NODES', '1').to_i
rspec_args = ENV.fetch('RSPEC_ARGS', '')
rspec_command = [File.join(BIN_DIR, 'bundle'), 'exec', 'knapsack', 'rspec']
rspec_command.concat(Shellwords.split(rspec_args)) unless rspec_args.empty?

if node_total <= 1
  run_command({ 'KNAPSACK' => 'true' }, rspec_command)
else
  FileUtils.rm_rf('coverage')

  processes = (0...node_total).map do |node_index|
    env = {
      'CI_NODE_TOTAL' => node_total.to_s,
      'CI_NODE_INDEX' => node_index.to_s,
      'KNAPSACK' => 'true',
      'SIMPLECOV_COMMAND_NAME' => "rspec-#{node_index}",
      'SIMPLECOV_SKIP_MINIMUM_COVERAGE' => 'true'
    }
    puts "$ #{env.map { |key, value| "#{key}=#{value}" }.join(' ')} #{rspec_command.join(' ')}"
    Process.spawn(env, *rspec_command)
  end

  statuses = processes.map { |pid| Process.wait2(pid).last }

  exit 1 unless statuses.all?(&:success?)

  run_command({}, [File.join(BIN_DIR, 'bundle'), 'exec', 'ruby', 'bin/simplecov_collate'])
end
