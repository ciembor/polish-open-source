# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Domain::RepositoryBackedPackageIdentity do
  it 'uses the repository full name as Terraform package identity' do
    manifest = PolishOpenSourceRank::Contexts::Packages::Domain::PackageManifest.new(
      ecosystem: 'terraform',
      confidence: 'medium',
      parse_status: 'partial'
    )

    enriched = described_class.apply(
      manifest,
      { platform: 'github', full_name: 'acme/terraform-aws-polish' }
    )

    expect(enriched.to_h).to include(
      package_name: 'acme/terraform-aws-polish',
      normalized_package_name: 'acme/terraform-aws-polish',
      repository_url: 'https://github.com/acme/terraform-aws-polish',
      parse_status: 'parsed',
      metadata: { identity_source: 'repository_full_name' }
    )
  end
end
