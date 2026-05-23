# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Domain::Parsers do
  it 'parses npm package.json manifests including scoped, private, and custom registry packages' do
    expect(parse('NpmPackageJsonParser', 'package.json', npm_json).to_h).to include(
      ecosystem: 'npm',
      package_name: '@scope/tool',
      normalized_package_name: '@scope/tool',
      repository_url: 'git+https://github.com/acme/tool.git',
      homepage_url: 'https://example.com',
      license: 'MIT',
      parse_status: 'parsed'
    )
    private_manifest = parse('NpmPackageJsonParser', 'package.json', '{"name":"internal","private":true}')
    expect(private_manifest).to have_attributes(private_package: true, parse_status: 'private')
    expect(parse('NpmPackageJsonParser', 'package.json', custom_npm_json)).to have_attributes(
      custom_registry: 'https://registry.example.com/',
      parse_status: 'custom_registry'
    )
    expect(parse('NpmPackageJsonParser', 'package.json', '{')).to have_attributes(parse_status: 'failed')
  end

  it 'parses RubyGems gemspecs conservatively without executing Ruby' do
    manifest = parse('RubyGemsGemspecParser', 'tool.gemspec', gemspec)

    expect(manifest.to_h).to include(
      ecosystem: 'rubygems',
      package_name: 'polish-tool',
      repository_url: 'https://github.com/acme/polish-tool',
      homepage_url: 'https://example.com/polish-tool',
      confidence: 'high',
      parse_status: 'parsed'
    )
    expect(parse('RubyGemsGemspecParser', 'dynamic.gemspec', 's.name = File.read("NAME")')).to have_attributes(
      confidence: 'medium',
      parse_status: 'partial'
    )
  end

  it 'parses Cargo manifests and unpublished workspace roots' do
    expect(parse('CargoTomlParser', 'Cargo.toml', cargo_toml).to_h).to include(
      ecosystem: 'crates',
      package_name: 'polish-crate',
      repository_url: 'https://github.com/acme/polish-crate',
      homepage_url: 'https://example.com/crate',
      license: 'MIT',
      parse_status: 'parsed'
    )
    manifest = parse('CargoTomlParser', 'Cargo.toml', cargo_workspace)
    expect(manifest).to have_attributes(parse_status: 'unpublished', package_name: nil)
    expect(manifest.metadata.fetch(:workspace_members)).to eq(%w[crates/* tools/cli])
  end

  it 'parses PyPI metadata from pyproject.toml, setup.cfg, and setup.py without executing Python' do
    expect(parse('PyProjectTomlParser', 'pyproject.toml', pyproject_toml)).to have_attributes(
      package_name: 'polish-python',
      confidence: 'high',
      parse_status: 'parsed'
    )
    expect(parse('SetupCfgParser', 'setup.cfg', setup_cfg)).to have_attributes(
      package_name: 'polish-cfg',
      homepage_url: 'https://example.com/cfg'
    )
    expect(parse('SetupPyParser', 'setup.py', 'setup(name="polish-setup")')).to have_attributes(
      package_name: 'polish-setup',
      confidence: 'medium',
      parse_status: 'partial'
    )
    expect(parse('SetupPyParser', 'setup.py', 'setup(name=os.system("rm -rf /"))')).to have_attributes(
      package_name: nil,
      confidence: 'low',
      parse_status: 'partial'
    )
  end

  it 'parses Hex manifests without executing Elixir or Erlang' do
    expect(parse('MixExsParser', 'mix.exs', 'def project, do: [app: :polish_hex]')).to have_attributes(
      package_name: 'polish-hex',
      parse_status: 'parsed'
    )
    expect(parse('GleamTomlParser', 'gleam.toml', 'name = "polish_gleam"')).to have_attributes(
      package_name: 'polish_gleam'
    )
    expect(parse('RebarConfigParser', 'rebar.config', '{app, polish_rebar}.')).to have_attributes(
      package_name: 'polish-rebar'
    )
    expect(parse('MixExsParser', 'mix.exs', 'System.cmd("rm", ["-rf", "/"])')).to have_attributes(
      confidence: 'medium',
      parse_status: 'partial'
    )
  end

  it 'parses Packagist and Go module manifests' do
    expect(parse('ComposerJsonParser', 'composer.json', composer_json).to_h).to include(
      ecosystem: 'packagist',
      package_name: 'vendor/package',
      repository_url: 'https://github.com/vendor/package',
      license: 'MIT, Apache-2.0',
      parse_status: 'parsed'
    )
    expect(parse('ComposerJsonParser', 'composer.json', '{"name":"invalid"}')).to have_attributes(
      parse_status: 'failed'
    )
    expect(parse('ComposerJsonParser', 'composer.json', '{')).to have_attributes(parse_status: 'failed')
    expect(parse('GoModParser', 'go.mod', "module github.com/acme/tool\n\ngo 1.22")).to have_attributes(
      ecosystem: 'go',
      package_name: 'github.com/acme/tool',
      parse_status: 'parsed'
    )
    expect(parse('GoModParser', 'go.mod', 'go 1.22')).to have_attributes(parse_status: 'partial')
  end

  def parse(parser_name, path, content)
    described_class.const_get(parser_name).new.parse(path: path, content: content)
  end

  def npm_json
    JSON.generate(
      name: '@scope/tool',
      repository: { url: 'git+https://github.com/acme/tool.git' },
      homepage: 'https://example.com',
      license: 'MIT',
      workspaces: ['packages/*']
    )
  end

  def custom_npm_json
    JSON.generate(name: 'custom', publishConfig: { registry: 'https://registry.example.com/' })
  end

  def gemspec
    <<~RUBY
      Gem::Specification.new do |s|
        s.name = "polish-tool"
        s.homepage = "https://example.com/polish-tool"
        s.metadata["source_code_uri"] = "https://github.com/acme/polish-tool"
        s.metadata["bug_tracker_uri"] = "https://github.com/acme/polish-tool/issues"
      end
    RUBY
  end

  def cargo_toml
    <<~TOML
      [package]
      name = "polish-crate"
      repository = "https://github.com/acme/polish-crate"
      homepage = "https://example.com/crate"
      license = "MIT"
    TOML
  end

  def cargo_workspace
    <<~TOML
      [package]
      publish = false

      [workspace]
      members = ["crates/*", "tools/cli"]
    TOML
  end

  def pyproject_toml
    <<~TOML
      [project]
      name = "polish-python"
      license = "MIT"
    TOML
  end

  def setup_cfg
    <<~CFG
      [metadata]
      name = "polish-cfg"
      url = "https://example.com/cfg"
      license = "MIT"
    CFG
  end

  def composer_json
    JSON.generate(
      name: 'vendor/package',
      support: { source: 'https://github.com/vendor/package', issues: 'https://example.com/issues' },
      license: %w[MIT Apache-2.0]
    )
  end
end
