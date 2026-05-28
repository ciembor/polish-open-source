# frozen_string_literal: true

class FakeGitHubTreeClient
  Response = Struct.new(:body, keyword_init: true)

  attr_reader :calls

  def initialize
    @calls = []
    @responses = {}
  end

  def stub(path, body:, params: {})
    responses[[path, params]] = Response.new(body: body)
  end

  def stub_error(path, error, params: {})
    responses[[path, params]] = error
  end

  def get(path, params: {})
    calls << { path: path, params: params }
    response = responses.fetch([path, params])
    raise response if response.is_a?(StandardError)

    response
  end

  private

  attr_reader :responses
end

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Infrastructure::GitHub::GitHubRepositoryTreeGateway do
  let(:client) { FakeGitHubTreeClient.new }
  let(:gateway) { described_class.new(client, max_blob_bytes: 8) }

  it 'loads repository metadata and blob tree entries through the existing GitHub client contract' do
    stub_repository_tree

    expect(gateway.repository('alice/app')).to eq(full_name: 'alice/app', default_branch: 'main')
    expect(gateway.tree('alice/app', ref: 'main')).to have_attributes(
      sha: 'tree-sha',
      truncated: true,
      entries: [{ path: 'package.json', sha: 'blob-sha' }]
    )
    expect(gateway.blob('alice/app', sha: 'blob-sha')).to eq('content')
    expect(client.calls.map { |call| call.fetch(:path) }).to eq(
      ['/repos/alice/app', '/repos/alice/app/git/trees/main', '/repos/alice/app/git/blobs/blob-sha']
    )
  end

  it 'ignores blobs above the configured size limit' do
    client.stub('/repos/alice/app/git/blobs/large-sha', body: { 'size' => 9, 'content' => Base64.strict_encode64('x') })

    expect(gateway.blob('alice/app', sha: 'large-sha')).to be_nil
  end

  it 'maps unavailable repositories to the package domain error' do
    client.stub_error(
      '/repos/alice/missing',
      PolishOpenSourceRank::Infrastructure::GitHubClient::NotFound.new('missing', status: 404, body: '{}')
    )
    client.stub_error(
      '/repos/alice/blocked',
      PolishOpenSourceRank::Infrastructure::GitHubClient::Error.new('blocked', status: 451, body: '{}')
    )

    expect { gateway.repository('alice/missing') }.to raise_error(
      PolishOpenSourceRank::Contexts::Packages::Application::RepositoryUnavailable,
      'GitHub repository unavailable: alice/missing'
    )
    expect { gateway.repository('alice/blocked') }.to raise_error(
      PolishOpenSourceRank::Contexts::Packages::Application::RepositoryUnavailable
    )
  end

  it 'maps unavailable repository trees to a recoverable package scan failure' do
    client.stub_error(
      '/repos/alice/conflict/git/trees/main',
      PolishOpenSourceRank::Infrastructure::GitHubClient::Error.new('conflict', status: 409, body: '{}'),
      params: { recursive: 1 }
    )

    expect { gateway.tree('alice/conflict', ref: 'main') }.to raise_error(
      PolishOpenSourceRank::Contexts::Packages::Application::RepositoryUnavailable,
      'GitHub repository unavailable: alice/conflict'
    )
  end

  it 'maps unexpected GitHub errors to a retryable repository scan failure' do
    error = PolishOpenSourceRank::Infrastructure::GitHubClient::Error.new('server error', status: 500, body: '{}')
    client.stub_error('/repos/alice/app/git/trees/main', error, params: { recursive: 1 })

    expect { gateway.tree('alice/app', ref: 'main') }.to raise_error(
      PolishOpenSourceRank::Contexts::Packages::Application::RetryableRepositoryScanFailure,
      'GitHub repository scan failed for alice/app: HTTP 500'
    )
  end

  it 'maps redirects to a retryable repository scan failure' do
    redirect = PolishOpenSourceRank::Infrastructure::GitHubClient::Error.new('moved', status: 301, body: '{}')
    client.stub_error('/repos/alice/app', redirect)

    expect { gateway.repository('alice/app') }.to raise_error(
      PolishOpenSourceRank::Contexts::Packages::Application::RetryableRepositoryScanFailure,
      'GitHub repository scan failed for alice/app: HTTP 301'
    )
  end

  it 'maps unavailable trees and blobs to the package domain error' do
    missing = PolishOpenSourceRank::Infrastructure::GitHubClient::NotFound.new('missing', status: 404, body: '{}')
    client.stub_error('/repos/alice/missing/git/trees/main', missing, params: { recursive: 1 })
    client.stub_error('/repos/alice/missing/git/blobs/blob-sha', missing)

    expect { gateway.tree('alice/missing', ref: 'main') }.to raise_error(
      PolishOpenSourceRank::Contexts::Packages::Application::RepositoryUnavailable
    )
    expect { gateway.blob('alice/missing', sha: 'blob-sha') }.to raise_error(
      PolishOpenSourceRank::Contexts::Packages::Application::RepositoryUnavailable
    )
  end

  def stub_repository_tree
    client.stub('/repos/alice/app', body: { 'full_name' => 'alice/app', 'default_branch' => 'main' })
    client.stub('/repos/alice/app/git/trees/main', params: { recursive: 1 }, body: tree_body)
    client.stub('/repos/alice/app/git/blobs/blob-sha', body: blob_body)
  end

  def tree_body
    {
      'sha' => 'tree-sha',
      'truncated' => true,
      'tree' => [
        { 'path' => 'package.json', 'sha' => 'blob-sha', 'type' => 'blob' },
        { 'path' => 'lib', 'sha' => 'tree-entry', 'type' => 'tree' }
      ]
    }
  end

  def blob_body
    { 'size' => 7, 'content' => Base64.strict_encode64('content') }
  end
end
