# frozen_string_literal: true

require 'net/protocol'
require 'openssl'
require 'socket'
require 'timeout'

module PolishOpenSourceRank
  module Interfaces
    module CLI
      module RetryableJobCommand
        MAX_JOB_ATTEMPTS = 2
        RETRYABLE_ERROR_CLASSES = [
          EOFError,
          Errno::ECONNRESET,
          Net::OpenTimeout,
          OpenSSL::SSL::SSLError,
          SocketError,
          Timeout::Error
        ].freeze
        RETRYABLE_ERROR_MESSAGES = [
          /database is locked/i,
          /execution expired/i,
          /open timeout/i,
          /unexpected eof while reading/i
        ].freeze

        private

        def run_with_job_retry(crawl_job_id)
          attempts = 0

          begin
            attempts += 1
            yield
          rescue Contexts::Operations::Application::CrawlInterrupted
            raise
          rescue StandardError => e
            raise unless retryable_job_error?(e) && attempts < MAX_JOB_ATTEMPTS

            crawl_jobs&.retry(crawl_job_id, "#{e.class}: #{e.message}") if crawl_job_id
            retry
          end
        end

        def retryable_job_error?(error)
          RETRYABLE_ERROR_CLASSES.any? { |klass| error.is_a?(klass) } ||
            RETRYABLE_ERROR_MESSAGES.any? { |pattern| error.message.match?(pattern) }
        end
      end
    end
  end
end
