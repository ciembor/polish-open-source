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
    expect(parse('NpmPackageJsonParser', 'package.json', '{"workspaces":["packages/*"]}')).to have_attributes(
      confidence: 'low',
      parse_status: 'partial'
    )
  end

  it 'treats non-literal and malformed npm package.json files as partial when they are not fetchable packages' do
    expect(parse('NpmPackageJsonParser', 'package.json', '')).to have_attributes(parse_status: 'partial')
    expect(parse('NpmPackageJsonParser', 'package.json',
                 "\xEF\xBB\xBF{\"name\":\"bom-package\"}")).to have_attributes(
                   package_name: 'bom-package',
                   parse_status: 'parsed'
                 )
    expect(parse('NpmPackageJsonParser', 'package.json',
                 "\xEF\xBB\xBF{\"name\":\"bom-package-binary\"}".b)).to have_attributes(
                   package_name: 'bom-package-binary',
                   parse_status: 'parsed'
                 )
    expect(parse('NpmPackageJsonParser', 'package.json',
                 '{"name":"broken-package" "version":"1.0.0"}')).to have_attributes(
                   parse_status: 'partial'
                 )
    expect(parse('NpmPackageJsonParser', 'package.json', '{')).to have_attributes(parse_status: 'failed')
    expect(parse('NpmPackageJsonParser', 'templates/package.json', '{%- if npm -%}')).to have_attributes(
      parse_status: 'partial'
    )
    expect(parse('NpmPackageJsonParser', 'resources/app/package.json',
                 'version=1.0.0')).to have_attributes(parse_status: 'partial')
    expect(parse('NpmPackageJsonParser', 'package.json',
                 "<<<<<<< HEAD\n{\"name\":\"merge-package\"}\n=======\n{}\n>>>>>>> branch")).to have_attributes(
                   parse_status: 'partial'
                 )
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
      package_name: 'polish_hex',
      parse_status: 'parsed'
    )
    expect(parse('GleamTomlParser', 'gleam.toml', 'name = "polish_gleam"')).to have_attributes(
      package_name: 'polish_gleam'
    )
    expect(parse('RebarConfigParser', 'rebar.config', '{app, polish_rebar}.')).to have_attributes(
      package_name: 'polish_rebar'
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
      parse_status: 'partial'
    )
    expect(parse('ComposerJsonParser', 'composer.json',
                 '{"name":"cognesy/instructor-{{PACKAGE_NAME}}"}')).to have_attributes(
                   parse_status: 'partial'
                 )
    expect(parse('ComposerJsonParser', 'composer.json', '')).to have_attributes(parse_status: 'partial')
    expect(parse('ComposerJsonParser', 'composer.json', '{')).to have_attributes(parse_status: 'failed')
    expect(parse('ComposerJsonParser',
                 'src/test/resources/org/psliwa/idea/composerJson/inspection/doctrine/composer.json',
                 <<~JSON)).to have_attributes(parse_status: 'partial')
                   {"name":"doctrine/orm","require-dev":{"phpunit/phpunit":"~4.0",<warning>"satooshi/php-coveralls":"dev-master"</warning>}}
                 JSON
    expect(parse('GoModParser', 'go.mod', "module github.com/acme/tool\n\ngo 1.22")).to have_attributes(
      ecosystem: 'go',
      package_name: 'github.com/acme/tool',
      parse_status: 'parsed'
    )
    expect(parse('GoModParser', 'vendor/gopkg.in/yaml.v2/go.mod',
                 "module \"gopkg.in/yaml.v2\"\n\ngo 1.22")).to have_attributes(
                   package_name: 'gopkg.in/yaml.v2',
                   normalized_package_name: 'gopkg.in/yaml.v2',
                   parse_status: 'parsed'
                 )
    expect(parse('GoModParser', 'go.mod', 'go 1.22')).to have_attributes(parse_status: 'partial')
  end

  it 'parses Homebrew formulae statically without executing Ruby' do
    expect(parse('HomebrewFormulaParser', 'Formula/polish-tool.rb', homebrew_formula).to_h).to include(
      ecosystem: 'homebrew',
      package_name: 'polish-tool',
      repository_url: 'https://github.com/acme/polish-tool/archive/v1.0.0.tar.gz',
      homepage_url: 'https://example.com/polish-tool',
      license: 'MIT',
      parse_status: 'parsed',
      metadata: {
        path: 'Formula/polish-tool.rb',
        source_url: 'https://github.com/acme/polish-tool/archive/v1.0.0.tar.gz'
      }
    )
    expect(parse('HomebrewFormulaParser', 'Formula/dynamic.rb', 'system "rm", "-rf", "/"')).to have_attributes(
      package_name: 'dynamic',
      parse_status: 'parsed'
    )
    expect(parse('HomebrewFormulaParser', 'Formula/multi-license.rb',
                 'license any_of: ["MIT", "Apache-2.0"]')).to have_attributes(
                   license: 'MIT, Apache-2.0'
                 )
  end

  it 'parses NuGet XML manifests without executing build tools' do
    expect(parse('NuGetXmlParser', 'src/Polish.Tool/Polish.Tool.csproj', csproj).to_h).to include(
      ecosystem: 'nuget',
      package_name: 'Polish.Tool',
      normalized_package_name: 'polish.tool',
      repository_url: 'https://github.com/acme/polish-tool',
      homepage_url: 'https://example.com/polish-tool',
      license: 'MIT',
      parse_status: 'parsed',
      metadata: {
        path: 'src/Polish.Tool/Polish.Tool.csproj',
        version: '1.2.3',
        package_references: [{ id: 'Newtonsoft.Json', version: '13.0.3' }]
      }
    )
    expect(parse('NuGetXmlParser', 'Polish.Tool.nuspec', nuspec)).to have_attributes(
      package_name: 'Polish.Nuspec.Tool',
      repository_url: 'https://github.com/acme/polish-nuspec-tool',
      homepage_url: 'https://example.com/polish-nuspec-tool',
      license: 'Apache-2.0',
      parse_status: 'parsed'
    )
    expect(parse('NuGetXmlParser', '.nuspec', nuspec)).to have_attributes(
      package_name: 'Polish.Nuspec.Tool',
      parse_status: 'parsed'
    )
    expect(parse('NuGetXmlParser', 'obj/Debug/generated.nuspec',
                 '<package><metadata><version>1.0.0</version></metadata></package>'))
      .to have_attributes(parse_status: 'partial')
  end

  it 'keeps NuGet central package versions diagnostic when no package id exists' do
    central_versions = parse('NuGetXmlParser', 'Directory.Packages.props', directory_packages_props)
    expect(central_versions).to have_attributes(package_name: nil, parse_status: 'partial')
    expect(central_versions.metadata.fetch(:package_versions)).to eq(
      [{ id: 'Serilog', version: '4.0.0' }, { id: 'Dapper', version: '2.1.35' }]
    )
    expect(parse('NuGetXmlParser', 'packages.config', '<packages />')).to have_attributes(parse_status: 'failed')
    expect(parse('NuGetXmlParser', 'broken.csproj', '<Project>')).to have_attributes(parse_status: 'failed')
  end

  it 'parses Maven POM and Gradle manifests without executing build tools' do
    expect(parse('MavenManifestParser', 'pom.xml', pom_xml).to_h).to include(
      ecosystem: 'maven',
      package_name: 'pl.example:polish-tool',
      repository_url: 'https://github.com/acme/polish-tool',
      homepage_url: 'https://example.com/polish-tool',
      license: 'Apache-2.0',
      parse_status: 'parsed',
      metadata: {
        path: 'pom.xml',
        group_id: 'pl.example',
        artifact_id: 'polish-tool',
        version: '1.0.0'
      }
    )
    expect(parse('MavenManifestParser', 'build.gradle', gradle_build)).to have_attributes(
      package_name: 'pl.example:gradle-tool',
      repository_url: 'https://github.com/acme/gradle-tool',
      parse_status: 'partial'
    )
    expect(parse('MavenManifestParser', 'settings.gradle.kts', 'rootProject.name = "gradle-tool"')).to have_attributes(
      package_name: nil,
      parse_status: 'partial'
    )
    malformed_comment_pom = pom_xml.sub(
      '</licenses>',
      <<~XML.chomp
        </licenses>
        <!-- <nativeImageArg> --report-unsupported-elements-at-runtime</nativeImageArg> -->
      XML
    )
    expect(parse('MavenManifestParser', 'pom.xml', malformed_comment_pom))
      .to have_attributes(package_name: 'pl.example:polish-tool', parse_status: 'parsed')
    expect(parse('MavenManifestParser', 'pom.xml', '<project>')).to have_attributes(parse_status: 'partial')
  end

  it 'parses Terraform and Conan manifests statically' do
    expect(parse('TerraformModuleParser', 'main.tf', terraform_module).to_h).to include(
      ecosystem: 'terraform',
      package_name: nil,
      parse_status: 'partial',
      metadata: {
        path: 'main.tf',
        required_providers: ['hashicorp/aws']
      }
    )
    expect(parse('ConanManifestParser', 'conanfile.py', conanfile_py).to_h).to include(
      ecosystem: 'conan',
      package_name: 'polish-conan',
      homepage_url: 'https://github.com/acme/polish-conan',
      license: 'MIT',
      parse_status: 'parsed'
    )
    expect(parse('ConanManifestParser', 'conanfile.txt', "name = polish-txt\n")).to have_attributes(
      package_name: 'polish-txt'
    )
  end

  it 'parses vcpkg manifests statically' do
    expect(parse('VcpkgJsonParser', 'vcpkg.json', vcpkg_json).to_h).to include(
      ecosystem: 'vcpkg',
      package_name: 'polish-vcpkg',
      homepage_url: 'https://github.com/acme/polish-vcpkg',
      license: 'MIT',
      parse_status: 'parsed'
    )
    expect(parse('VcpkgJsonParser', 'vcpkg.json', '{"version":"1.0.0"}')).to have_attributes(
      parse_status: 'partial'
    )
    expect(parse('VcpkgJsonParser', 'vcpkg.json', '{')).to have_attributes(parse_status: 'failed')
  end

  it 'parses SwiftPM and pub.dev manifests statically' do
    expect(parse('SwiftPackageParser', 'Package.swift', swift_package)).to have_attributes(
      ecosystem: 'swiftpm',
      package_name: 'PolishSwift',
      parse_status: 'parsed'
    )
    expect(parse('PubspecYamlParser', 'pubspec.yaml', pubspec_yaml).to_h).to include(
      ecosystem: 'pub',
      package_name: 'polish_pub',
      repository_url: 'https://github.com/acme/polish_pub',
      homepage_url: 'https://example.com/polish_pub',
      parse_status: 'parsed'
    )
  end

  it 'parses APT, RPM, and Nix package manifests statically' do
    expect(parse('DebianControlParser', 'debian/control', debian_control).to_h).to include(
      ecosystem: 'apt',
      package_name: 'polish-apt',
      homepage_url: 'https://example.com/polish-apt',
      parse_status: 'parsed'
    )
    expect(parse('DebianControlParser', 'debian/tests/control', 'Tests: smoke')).to have_attributes(
      parse_status: 'partial'
    )
    expect(parse('RpmSpecParser', 'polish-rpm.spec', rpm_spec).to_h).to include(
      ecosystem: 'rpm',
      package_name: 'polish-rpm',
      repository_url: 'https://github.com/acme/polish-rpm/archive/v1.0.0.tar.gz',
      homepage_url: 'https://example.com/polish-rpm',
      license: 'MIT',
      parse_status: 'parsed'
    )
    expect(parse('RpmSpecParser', 'pyinstaller.spec', 'block_cipher = None')).to have_attributes(
      parse_status: 'partial'
    )
    expect(parse('NixPackageParser', 'default.nix', nix_package).to_h).to include(
      ecosystem: 'nix',
      package_name: 'polish-nix',
      repository_url: 'https://github.com/acme/polish-nix',
      homepage_url: 'https://github.com/acme/polish-nix',
      license: 'mit',
      parse_status: 'parsed'
    )
    expect(parse('NixPackageParser', 'flake.nix', 'description = "Polish flake";')).to have_attributes(
      package_name: 'Polish flake'
    )
  end

  it 'parses CRAN and CPAN manifests statically' do
    expect(parse('CranDescriptionParser', 'DESCRIPTION', cran_description).to_h).to include(
      ecosystem: 'cran',
      package_name: 'polishcran',
      homepage_url: 'https://github.com/acme/polishcran',
      license: 'MIT',
      parse_status: 'parsed'
    )
    expect(parse('CranDescriptionParser', 'inst/examples/demo/DESCRIPTION', 'Version: 1.0')).to have_attributes(
      parse_status: 'partial'
    )
    expect(parse('CpanManifestParser', 'META.json', cpan_meta_json).to_h).to include(
      ecosystem: 'cpan',
      package_name: 'Acme-Polish',
      repository_url: 'https://github.com/acme/acme-polish',
      license: 'perl_5',
      parse_status: 'parsed'
    )
    expect(parse('CpanManifestParser', 'Makefile.PL',
                 "WriteMakefile(NAME => 'Acme::Polish', LICENSE => 'perl')")).to have_attributes(
                   package_name: 'Acme-Polish',
                   parse_status: 'partial'
                 )
    expect(parse('CpanManifestParser', 'META.yml', "name: Acme-Yaml\nversion: 1.0.0")).to have_attributes(
      package_name: 'Acme-Yaml'
    )
    expect(parse('CpanManifestParser', 'META.json', '{')).to have_attributes(parse_status: 'failed')
  end

  it 'parses Hackage manifests statically' do
    expect(parse('HackageManifestParser', 'polish.cabal', hackage_cabal).to_h).to include(
      ecosystem: 'hackage',
      package_name: 'polish-hackage',
      repository_url: 'https://github.com/acme/polish-hackage',
      license: 'BSD-3-Clause',
      parse_status: 'parsed'
    )
  end

  it 'parses Clojars manifests statically' do
    expect(parse('ClojarsManifestParser', 'project.clj', clojars_project).to_h).to include(
      ecosystem: 'clojars',
      package_name: 'pl.example/polish-clj',
      repository_url: 'https://github.com/acme/polish-clj',
      license: 'EPL-2.0',
      parse_status: 'parsed'
    )
    expect(parse('ClojarsManifestParser', 'deps.edn', '{:project/name "pl.example/deps"}')).to have_attributes(
      package_name: 'pl.example/deps',
      parse_status: 'partial'
    )
    expect(parse('ClojarsManifestParser', 'build.boot', "(def project 'pl.example/boot)")).to have_attributes(
      package_name: 'pl.example/boot'
    )
  end

  it 'parses Julia and Conda manifests statically' do
    expect(parse('JuliaProjectTomlParser', 'Project.toml', julia_project).to_h).to include(
      ecosystem: 'julia',
      package_name: 'PolishJulia',
      repository_url: 'https://github.com/acme/PolishJulia.jl',
      parse_status: 'parsed'
    )
    expect(parse('CondaManifestParser', 'meta.yaml', conda_meta).to_h).to include(
      ecosystem: 'conda',
      package_name: 'polish-conda',
      homepage_url: 'https://example.com/polish-conda',
      license: 'BSD-3-Clause',
      parse_status: 'parsed'
    )
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

  def homebrew_formula
    <<~RUBY
      class PolishTool < Formula
        homepage "https://example.com/polish-tool"
        url "https://github.com/acme/polish-tool/archive/v1.0.0.tar.gz"
        license "MIT"
      end
    RUBY
  end

  def csproj
    <<~XML
      <Project Sdk="Microsoft.NET.Sdk">
        <PropertyGroup>
          <PackageId>Polish.Tool</PackageId>
          <PackageVersion>1.2.3</PackageVersion>
          <RepositoryUrl>https://github.com/acme/polish-tool</RepositoryUrl>
          <PackageProjectUrl>https://example.com/polish-tool</PackageProjectUrl>
          <PackageLicenseExpression>MIT</PackageLicenseExpression>
        </PropertyGroup>
        <ItemGroup>
          <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
        </ItemGroup>
      </Project>
    XML
  end

  def nuspec
    <<~XML
      <package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
        <metadata>
          <id>Polish.Nuspec.Tool</id>
          <version>2.0.0</version>
          <projectUrl>https://example.com/polish-nuspec-tool</projectUrl>
          <repository type="git" url="https://github.com/acme/polish-nuspec-tool" />
          <license type="expression">Apache-2.0</license>
        </metadata>
      </package>
    XML
  end

  def directory_packages_props
    <<~XML
      <Project>
        <ItemGroup>
          <PackageVersion Include="Serilog" Version="4.0.0" />
          <PackageVersion Include="Dapper" Version="2.1.35" />
        </ItemGroup>
      </Project>
    XML
  end

  def pom_xml
    <<~XML
      <project xmlns="http://maven.apache.org/POM/4.0.0">
        <modelVersion>4.0.0</modelVersion>
        <groupId>pl.example</groupId>
        <artifactId>polish-tool</artifactId>
        <version>1.0.0</version>
        <url>https://example.com/polish-tool</url>
        <scm>
          <url>https://github.com/acme/polish-tool</url>
        </scm>
        <licenses>
          <license>
            <name>Apache-2.0</name>
          </license>
        </licenses>
      </project>
    XML
  end

  def gradle_build
    <<~GRADLE
      group = 'pl.example'
      version = '2.0.0'
      archivesName = 'gradle-tool'
      url = 'https://example.com/gradle-tool'
      scm = 'https://github.com/acme/gradle-tool'
      license = 'MIT'
    GRADLE
  end

  def terraform_module
    <<~HCL
      terraform {
        required_providers {
          aws = {
            source = "hashicorp/aws"
          }
        }
      }
    HCL
  end

  def conanfile_py
    <<~PY
      from conan import ConanFile

      class PolishConan(ConanFile):
          name = "polish-conan"
          version = "1.0.0"
          url = "https://github.com/acme/polish-conan"
          license = "MIT"
    PY
  end

  def vcpkg_json
    JSON.generate(
      name: 'polish-vcpkg',
      version: '1.0.0',
      homepage: 'https://github.com/acme/polish-vcpkg',
      license: 'MIT'
    )
  end

  def swift_package
    <<~SWIFT
      // swift-tools-version: 5.9
      import PackageDescription

      let package = Package(
        name: "PolishSwift",
        platforms: [.iOS(.v15)]
      )
    SWIFT
  end

  def pubspec_yaml
    <<~YAML
      name: polish_pub
      version: 1.0.0
      homepage: https://example.com/polish_pub
      repository: https://github.com/acme/polish_pub
    YAML
  end

  def debian_control
    <<~CONTROL
      Source: polish-apt
      Maintainer: Polish Maintainer <maintainer@example.com>
      Standards-Version: 4.7.0
      Homepage: https://example.com/polish-apt

      Package: polish-apt
      Architecture: any
    CONTROL
  end

  def rpm_spec
    <<~SPEC
      Name: polish-rpm
      Version: 1.0.0
      License: MIT
      URL: https://example.com/polish-rpm
      Source0: https://github.com/acme/polish-rpm/archive/v1.0.0.tar.gz
    SPEC
  end

  def nix_package
    <<~NIX
      { lib, stdenv }:

      stdenv.mkDerivation {
        pname = "polish-nix";
        version = "1.0.0";
        meta = {
          homepage = "https://github.com/acme/polish-nix";
          license = lib.licenses.mit;
        };
      }
    NIX
  end

  def cran_description
    <<~DESCRIPTION
      Package: polishcran
      Version: 1.0.0
      URL: https://github.com/acme/polishcran
      License: MIT
    DESCRIPTION
  end

  def cpan_meta_json
    JSON.generate(
      name: 'Acme-Polish',
      version: '1.0.0',
      license: ['perl_5'],
      resources: {
        repository: { url: 'https://github.com/acme/acme-polish' },
        homepage: 'https://example.com/acme-polish'
      }
    )
  end

  def hackage_cabal
    <<~CABAL
      name: polish-hackage
      version: 0.1.0.0
      homepage: https://example.com/polish-hackage
      license: BSD-3-Clause
      source-repository head
        type: git
        location: https://github.com/acme/polish-hackage
    CABAL
  end

  def clojars_project
    <<~CLOJURE
      (defproject pl.example/polish-clj "1.0.0"
        :url "https://github.com/acme/polish-clj"
        :license {:name "EPL-2.0"})
    CLOJURE
  end

  def julia_project
    <<~TOML
      name = "PolishJulia"
      uuid = "11111111-1111-1111-1111-111111111111"
      version = "1.0.0"
      repo = "https://github.com/acme/PolishJulia.jl"
    TOML
  end

  def conda_meta
    <<~YAML
      package:
        name: polish-conda
        version: 1.0.0
      about:
        home: https://example.com/polish-conda
        dev_url: https://github.com/acme/polish-conda
        license: BSD-3-Clause
    YAML
  end
end
