# frozen_string_literal: true

require 'base64'
require 'json'

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module GitHub
          class GitHubRepositoryTreeGateway
            DEFAULT_MAX_BLOB_BYTES = 1_048_576
            UNAVAILABLE_STATUSES = [404, 409, 451].freeze
            EMPTY_REPOSITORY_MESSAGE = 'Git Repository is empty.'
            BLOCKED_REPOSITORY_MESSAGE = 'Repository access blocked'

            def initialize(client, max_blob_bytes: DEFAULT_MAX_BLOB_BYTES)
              @client = client
              @max_blob_bytes = max_blob_bytes
            end

            def repository(full_name)
              body = github_response(full_name) { get(repository_path(full_name)) }.body
              { full_name: body.fetch('full_name'), default_branch: body.fetch('default_branch') }
            end

            def tree(full_name, ref:)
              body = github_tree_response(full_name) do
                get("#{repository_path(full_name)}/git/trees/#{ref}", params: { recursive: 1 })
              end.body
              Domain::RepositoryTree.new(
                sha: body.fetch('sha'),
                entries: tree_entries(body.fetch('tree', [])),
                truncated: body.fetch('truncated', false)
              )
            end

            def blob(full_name, sha:)
              body = github_response(full_name) { get("#{repository_path(full_name)}/git/blobs/#{sha}") }.body
              return if body.fetch('size', 0).to_i > max_blob_bytes

              Base64.decode64(body.fetch('content').to_s.delete("\n"))
            end

            private

            attr_reader :client, :max_blob_bytes

            def get(path, params: {})
              client.get(path, params: params)
            end

            def github_response(full_name)
              yield
            rescue PolishOpenSourceRank::Infrastructure::GitHubClient::Error => e
              raise_unavailable(full_name) if blocked_repository_error?(e)
              raise_unavailable(full_name) if UNAVAILABLE_STATUSES.include?(e.status)

              raise_retryable_failure(full_name, e)
            end

            def github_tree_response(full_name)
              yield
            rescue PolishOpenSourceRank::Infrastructure::GitHubClient::Error => e
              return empty_tree_response if empty_repository_tree_error?(e)

              raise_unavailable(full_name) if blocked_repository_error?(e)
              raise_unavailable(full_name) if UNAVAILABLE_STATUSES.include?(e.status)

              raise_retryable_failure(full_name, e)
            end

            def empty_tree_response
              PolishOpenSourceRank::Infrastructure::GitHubClient::Response.new(
                status: 200,
                headers: {},
                body: { 'sha' => nil, 'tree' => [], 'truncated' => false }
              )
            end

            def empty_repository_tree_error?(error)
              error.status == 409 && error_body_message(error) == EMPTY_REPOSITORY_MESSAGE
            end

            def blocked_repository_error?(error)
              error.status == 403 && error_body_message(error) == BLOCKED_REPOSITORY_MESSAGE
            end

            def error_body_message(error)
              JSON.parse(error.body.to_s).fetch('message', nil)
            rescue JSON::ParserError
              nil
            end

            def raise_retryable_failure(full_name, error)
              raise Application::RetryableRepositoryScanFailure,
                    "GitHub repository scan failed for #{full_name}: HTTP #{error.status}"
            end

            def repository_path(full_name)
              owner, name = full_name.split('/', 2)
              "/repos/#{owner}/#{name}"
            end

            def tree_entries(entries)
              entries.select { |entry| entry.fetch('type') == 'blob' }
                     .map { |entry| { path: entry.fetch('path'), sha: entry.fetch('sha') } }
            end

            def raise_unavailable(full_name)
              raise Application::RepositoryUnavailable, "GitHub repository unavailable: #{full_name}"
            end
          end
        end
      end
    end
  end
end
