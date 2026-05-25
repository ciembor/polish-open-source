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
      'src/Polish.Tool/Polish.Tool.csproj',
      'src/Polish.Tool/Polish.Tool.fsproj',
      'src/Polish.Tool/Polish.Tool.vbproj',
      'Polish.Tool.nuspec',
      'Directory.Packages.props',
      'pom.xml',
      'build.gradle',
      'build.gradle.kts',
      'settings.gradle',
      'settings.gradle.kts',
      'mix.exs',
      'gleam.toml',
      'rebar.config',
      'composer.json',
      'go.mod',
      'main.tf',
      'conanfile.py',
      'vcpkg.json',
      'Package.swift',
      'pubspec.yaml',
      'debian/control',
      'packaging/tool.spec',
      'flake.nix',
      'default.nix',
      'shell.nix',
      'DESCRIPTION',
      'META.json',
      'META.yml',
      'cpanfile',
      'Makefile.PL',
      'polish.cabal',
      'package.yaml',
      'deps.edn',
      'project.clj',
      'build.boot',
      'Project.toml',
      'meta.yaml',
      'environment.yml',
      'target/generated/Cargo.toml',
      'README.md'
    ]
  end

  def expected_manifest_pairs
    [
      ['apt', 'debian/control'],
      ['clojars', 'build.boot'],
      ['clojars', 'deps.edn'],
      ['clojars', 'project.clj'],
      ['conan', 'conanfile.py'],
      ['conda', 'environment.yml'],
      ['conda', 'meta.yaml'],
      ['cpan', 'META.json'],
      ['cpan', 'META.yml'],
      ['cpan', 'Makefile.PL'],
      ['cpan', 'cpanfile'],
      ['cran', 'DESCRIPTION'],
      ['crates', 'Cargo.toml'],
      ['crates', 'crates/member/Cargo.toml'],
      ['go', 'go.mod'],
      ['hackage', 'package.yaml'],
      ['hackage', 'polish.cabal'],
      ['hex', 'gleam.toml'],
      ['hex', 'mix.exs'],
      ['hex', 'rebar.config'],
      ['homebrew', 'Formula/polish-tool.rb'],
      ['homebrew', 'tap/Formula/nested-tool.rb'],
      ['julia', 'Project.toml'],
      ['maven', 'build.gradle'],
      ['maven', 'build.gradle.kts'],
      ['maven', 'pom.xml'],
      ['maven', 'settings.gradle'],
      ['maven', 'settings.gradle.kts'],
      ['nix', 'default.nix'],
      ['nix', 'flake.nix'],
      ['npm', 'apps/web/package.json'],
      ['nuget', 'Directory.Packages.props'],
      ['nuget', 'Polish.Tool.nuspec'],
      ['nuget', 'src/Polish.Tool/Polish.Tool.csproj'],
      ['nuget', 'src/Polish.Tool/Polish.Tool.fsproj'],
      ['nuget', 'src/Polish.Tool/Polish.Tool.vbproj'],
      ['packagist', 'composer.json'],
      ['pub', 'pubspec.yaml'],
      ['pypi', 'pyproject.toml'],
      ['pypi', 'setup.cfg'],
      ['pypi', 'setup.py'],
      ['rpm', 'packaging/tool.spec'],
      ['rubygems', 'pkg/tool.gemspec'],
      ['swiftpm', 'Package.swift'],
      ['terraform', 'main.tf'],
      ['vcpkg', 'vcpkg.json']
    ]
  end
end
