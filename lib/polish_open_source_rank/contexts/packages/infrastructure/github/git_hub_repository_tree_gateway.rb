# frozen_string_literal: true

require 'base64'

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module GitHub
          class GitHubRepositoryTreeGateway
            DEFAULT_MAX_BLOB_BYTES = 1_048_576

            def initialize(client, max_blob_bytes: DEFAULT_MAX_BLOB_BYTES)
              @client = client
              @max_blob_bytes = max_blob_bytes
            end

            def repository(full_name)
              body = get(repository_path(full_name)).body
              { full_name: body.fetch('full_name'), default_branch: body.fetch('default_branch') }
            rescue PolishOpenSourceRank::Infrastructure::GitHubClient::NotFound
              raise_unavailable(full_name)
            end

            def tree(full_name, ref:)
              body = get("#{repository_path(full_name)}/git/trees/#{ref}", params: { recursive: 1 }).body
              Domain::RepositoryTree.new(
                sha: body.fetch('sha'),
                entries: tree_entries(body.fetch('tree', [])),
                truncated: body.fetch('truncated', false)
              )
            rescue PolishOpenSourceRank::Infrastructure::GitHubClient::NotFound
              raise_unavailable(full_name)
            end

            def blob(full_name, sha:)
              body = get("#{repository_path(full_name)}/git/blobs/#{sha}").body
              return if body.fetch('size', 0).to_i > max_blob_bytes

              Base64.decode64(body.fetch('content').to_s.delete("\n"))
            rescue PolishOpenSourceRank::Infrastructure::GitHubClient::NotFound
              raise_unavailable(full_name)
            end

            private

            attr_reader :client, :max_blob_bytes

            def get(path, params: {})
              client.get(path, params: params)
            rescue PolishOpenSourceRank::Infrastructure::GitHubClient::Error => e
              raise_unavailable(path) if e.status == 451

              raise
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
