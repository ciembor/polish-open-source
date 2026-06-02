# frozen_string_literal: true

RSpec.describe File do
  let(:root) { described_class.expand_path('../..', __dir__) }

  it 'health-gates deploys and keeps a one-step rollback slot' do
    script = described_class.read(described_class.join(root, 'scripts/deploy.sh'))

    expect(script).to include(
      'DEPLOY_ACTION',
      'PREVIOUS_IMAGE_NAME',
      'ROLLBACK_CANDIDATE_IMAGE_NAME',
      'assert_production_session_secret',
      'SESSION_SECRET in ${env_file} must be at least 64 characters before deploy.',
      'curl -fsSL -o /dev/null "http://127.0.0.1:9293/healthz"',
      'curl -fsSL -o /dev/null "${PUBLIC_BASE_URL}/latest"',
      'No previous image available for rollback'
    )
  end

  it 'lets GitHub Actions dispatch either a deploy or a one-step rollback' do
    workflow = described_class.read(described_class.join(root, '.github/workflows/deploy.yml'))

    expect(workflow).to include(
      'workflow_dispatch:',
      'type: choice',
      '- deploy',
      '- rollback',
      'DEPLOY_ACTION:',
      'run: scripts/deploy.sh "$DEPLOY_ACTION"'
    )
  end

  it 'builds and smoke-tests the production container before deploy' do
    workflow = described_class.read(described_class.join(root, '.github/workflows/deploy.yml'))

    expect(workflow).to include(
      'container-smoke:',
      'ruby-version: "4.0.5"',
      'docker build --pull -t polish-open-source-rank:ci .',
      'SESSION_SECRET=container-smoke-session-secret-for-polish-open-source-rank-ci-2026',
      'curl -fsS http://127.0.0.1:9293/healthz',
      'container must not run as root',
      'runtime dirs are not writable',
      '- container-smoke'
    )
  end
end
