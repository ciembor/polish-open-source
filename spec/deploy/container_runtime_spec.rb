# frozen_string_literal: true

RSpec.describe File do
  let(:root) { described_class.expand_path('../..', __dir__) }

  it 'pins the production image to the project Ruby runtime and runs as a non-root app user' do
    dockerfile = described_class.read(described_class.join(root, 'Dockerfile'))

    expect(dockerfile).to include(
      'FROM docker.io/library/ruby:4.0.5-slim-bookworm',
      'ARG APP_UID=1000',
      'ARG APP_GID=1000',
      'BUNDLE_APP_CONFIG=/app/tmp/bundle',
      'HOME=/app/tmp',
      'TMPDIR=/app/tmp',
      'useradd --uid "${APP_UID}" --gid app',
      'chown -R app:app db log tmp',
      'USER app:app'
    )
  end
end
