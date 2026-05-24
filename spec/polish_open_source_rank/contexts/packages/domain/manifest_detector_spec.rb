# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Domain::ManifestDetector do
  it 'detects package manifests for MVP ecosystems in deterministic order' do
    manifests = described_class.detect_paths(manifest_tree_paths)

    expect(manifest_pairs(manifests)).to eq(expected_manifest_pairs)
  end

  it 'ignores generated and vendored directories' do
    manifests = described_class.detect_paths(
      [
        '.git/hooks/package.json',
        'build/package.json',
        'dist/package.json',
        'vendor/bundle/ruby/gems/foo.gemspec'
      ]
    )

    expect(manifests).to be_empty
  end

  def manifest_pairs(manifests)
    manifests.map { |manifest| [manifest.ecosystem, manifest.path] }
  end

  def manifest_tree_paths
    [
      'apps/web/package.json',
      'node_modules/ignored/package.json',
      'pkg/tool.gemspec',
      'Cargo.toml',
      'crates/member/Cargo.toml',
      'pyproject.toml',
      'setup.cfg',
      'setup.py',
      'Formula/polish-tool.rb',
      'tap/Formula/nested-tool.rb',
      'mix.exs',
      'gleam.toml',
      'rebar.config',
      'composer.json',
      'go.mod',
      'target/generated/Cargo.toml',
      'README.md'
    ]
  end

  def expected_manifest_pairs
    [
      ['crates', 'Cargo.toml'],
      ['crates', 'crates/member/Cargo.toml'],
      ['go', 'go.mod'],
      ['hex', 'gleam.toml'],
      ['hex', 'mix.exs'],
      ['hex', 'rebar.config'],
      ['homebrew', 'Formula/polish-tool.rb'],
      ['homebrew', 'tap/Formula/nested-tool.rb'],
      ['npm', 'apps/web/package.json'],
      ['packagist', 'composer.json'],
      ['pypi', 'pyproject.toml'],
      ['pypi', 'setup.cfg'],
      ['pypi', 'setup.py'],
      ['rubygems', 'pkg/tool.gemspec']
    ]
  end
end
