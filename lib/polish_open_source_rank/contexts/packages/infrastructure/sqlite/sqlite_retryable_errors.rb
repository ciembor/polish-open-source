# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module SQLite
          module SQLiteRetryableErrors
            SQLITE_RETRYABLE_MESSAGES = [
              /database is locked/i,
              /database table is locked/i,
              /database schema is locked/i,
              /FOREIGN KEY constraint failed/i
            ].freeze

            private

            def translate_retryable_sqlite_failure
              yield
            rescue Sequel::DatabaseError => e
              raise retryable_repository_scan_failure(e) if retryable_sqlite_failure?(e)

              raise
            end

            def retryable_repository_scan_failure(error)
              Application::RetryableRepositoryScanFailure.new(
                "Retryable SQLite persistence failure: #{error.message}"
              )
            end

            def retryable_sqlite_failure?(error)
              SQLITE_RETRYABLE_MESSAGES.any? { |pattern| error.message.match?(pattern) }
            end
          end
        end
      end
    end
  end
end
