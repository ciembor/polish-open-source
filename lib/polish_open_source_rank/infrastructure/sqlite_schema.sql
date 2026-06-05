-- @owner ranking
-- @readers publication, operations, packages
CREATE TABLE IF NOT EXISTS sync_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  period_start TEXT NOT NULL UNIQUE,
  period_end TEXT NOT NULL,
  status TEXT NOT NULL,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  error TEXT
);

-- @owner operations
CREATE TABLE IF NOT EXISTS crawl_job_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  command TEXT NOT NULL,
  arguments_json TEXT NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  error TEXT,
  updated_at TEXT NOT NULL
);

-- @owner ranking
-- @readers operations
CREATE TABLE IF NOT EXISTS candidate_users (
  period_start TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'github',
  github_id INTEGER NOT NULL,
  login TEXT NOT NULL,
  source_query TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  error TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(period_start, platform, login)
);

-- @owner ranking
-- @readers operations
CREATE TABLE IF NOT EXISTS candidate_organizations (
  period_start TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'github',
  github_id INTEGER NOT NULL,
  login TEXT NOT NULL,
  source_query TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  error TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(period_start, platform, login)
);

-- @owner ranking
-- @readers publication, community
CREATE TABLE IF NOT EXISTS users (
  platform TEXT NOT NULL DEFAULT 'github',
  github_id INTEGER NOT NULL,
  login TEXT NOT NULL,
  name TEXT,
  location_raw TEXT,
  city TEXT,
  country TEXT,
  email TEXT,
  homepage TEXT,
  html_url TEXT NOT NULL,
  avatar_url TEXT,
  avatar_hidden INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(platform, github_id),
  UNIQUE(platform, login)
);

-- @owner ranking
-- @readers publication
CREATE TABLE IF NOT EXISTS organizations (
  platform TEXT NOT NULL DEFAULT 'github',
  github_id INTEGER NOT NULL,
  login TEXT NOT NULL,
  name TEXT,
  location_raw TEXT,
  city TEXT,
  country TEXT,
  email TEXT,
  homepage TEXT,
  html_url TEXT NOT NULL,
  avatar_url TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(platform, github_id),
  UNIQUE(platform, login)
);

-- @owner ranking
-- @readers publication, languages, community, operations
CREATE TABLE IF NOT EXISTS user_monthly_stats (
  period_start TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'github',
  user_github_id INTEGER NOT NULL,
  login TEXT NOT NULL,
  city TEXT,
  country TEXT,
  public_repo_count INTEGER NOT NULL,
  total_stars INTEGER NOT NULL,
  monthly_stars_delta INTEGER NOT NULL,
  merged_pull_requests_count INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(period_start, platform, user_github_id),
  FOREIGN KEY(platform, user_github_id) REFERENCES users(platform, github_id)
);

-- @owner ranking
-- @readers publication, languages, operations
CREATE TABLE IF NOT EXISTS organization_monthly_stats (
  period_start TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'github',
  organization_github_id INTEGER NOT NULL,
  login TEXT NOT NULL,
  city TEXT,
  country TEXT,
  public_repo_count INTEGER NOT NULL,
  total_stars INTEGER NOT NULL,
  monthly_stars_delta INTEGER NOT NULL,
  merged_pull_requests_count INTEGER NOT NULL DEFAULT 0,
  members_count INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(period_start, platform, organization_github_id),
  FOREIGN KEY(platform, organization_github_id) REFERENCES organizations(platform, github_id)
);

-- @owner ranking
-- @readers publication, languages, packages, operations
CREATE TABLE IF NOT EXISTS repositories (
  platform TEXT NOT NULL DEFAULT 'github',
  github_id INTEGER NOT NULL,
  owner_github_id INTEGER NOT NULL,
  owner_login TEXT NOT NULL,
  name TEXT NOT NULL,
  full_name TEXT NOT NULL,
  description TEXT,
  html_url TEXT NOT NULL,
  homepage TEXT,
  language TEXT,
  fork INTEGER NOT NULL,
  archived INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(platform, github_id),
  UNIQUE(platform, full_name),
  FOREIGN KEY(platform, owner_github_id) REFERENCES users(platform, github_id)
);

-- @owner ranking
-- @readers publication, languages, packages, operations
CREATE TABLE IF NOT EXISTS organization_repositories (
  platform TEXT NOT NULL DEFAULT 'github',
  github_id INTEGER NOT NULL,
  organization_github_id INTEGER NOT NULL,
  organization_login TEXT NOT NULL,
  name TEXT NOT NULL,
  full_name TEXT NOT NULL,
  description TEXT,
  html_url TEXT NOT NULL,
  homepage TEXT,
  language TEXT,
  fork INTEGER NOT NULL,
  archived INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(platform, github_id),
  UNIQUE(platform, full_name),
  FOREIGN KEY(platform, organization_github_id) REFERENCES organizations(platform, github_id)
);

-- @owner ranking
-- @readers publication, languages, operations
CREATE TABLE IF NOT EXISTS repository_monthly_stats (
  period_start TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'github',
  repository_github_id INTEGER NOT NULL,
  owner_github_id INTEGER NOT NULL,
  owner_login TEXT NOT NULL,
  owner_city TEXT,
  owner_country TEXT,
  stargazers_count INTEGER NOT NULL,
  monthly_stars_delta INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(period_start, platform, repository_github_id),
  FOREIGN KEY(platform, repository_github_id) REFERENCES repositories(platform, github_id),
  FOREIGN KEY(platform, owner_github_id) REFERENCES users(platform, github_id)
);

-- @owner ranking
-- @readers publication, languages, operations
CREATE TABLE IF NOT EXISTS organization_repository_monthly_stats (
  period_start TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'github',
  repository_github_id INTEGER NOT NULL,
  organization_github_id INTEGER NOT NULL,
  organization_login TEXT NOT NULL,
  organization_city TEXT,
  organization_country TEXT,
  stargazers_count INTEGER NOT NULL,
  monthly_stars_delta INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(period_start, platform, repository_github_id),
  FOREIGN KEY(platform, repository_github_id) REFERENCES organization_repositories(platform, github_id),
  FOREIGN KEY(platform, organization_github_id) REFERENCES organizations(platform, github_id)
);

-- @owner ranking
CREATE TABLE IF NOT EXISTS repository_star_observations (
  period_start TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'github',
  repository_github_id INTEGER NOT NULL,
  stargazers_count INTEGER NOT NULL,
  observed_at TEXT NOT NULL,
  PRIMARY KEY(period_start, platform, repository_github_id)
);

-- @owner ranking
CREATE TABLE IF NOT EXISTS organization_repository_star_observations (
  period_start TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'github',
  repository_github_id INTEGER NOT NULL,
  stargazers_count INTEGER NOT NULL,
  observed_at TEXT NOT NULL,
  PRIMARY KEY(period_start, platform, repository_github_id)
);

-- @owner ranking
-- @readers operations
CREATE TABLE IF NOT EXISTS api_request_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  platform TEXT NOT NULL,
  path TEXT NOT NULL,
  status INTEGER NOT NULL,
  recorded_at TEXT NOT NULL
);

-- @owner operations
CREATE TABLE IF NOT EXISTS job_work_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  job_run_id INTEGER,
  period_start TEXT NOT NULL,
  job_kind TEXT NOT NULL,
  stage TEXT NOT NULL,
  unit_kind TEXT NOT NULL,
  platform TEXT,
  ecosystem TEXT,
  subject_id TEXT,
  subject_label TEXT,
  status TEXT NOT NULL,
  started_at TEXT NOT NULL,
  finished_at TEXT NOT NULL,
  duration_ms INTEGER NOT NULL,
  error TEXT
);

-- @owner community
CREATE TABLE IF NOT EXISTS discord_connections (
  platform TEXT NOT NULL,
  user_github_id INTEGER NOT NULL,
  discord_user_id TEXT NOT NULL,
  discord_username TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(platform, user_github_id),
  UNIQUE(discord_user_id),
  FOREIGN KEY(platform, user_github_id) REFERENCES users(platform, github_id)
);

-- @owner community
CREATE TABLE IF NOT EXISTS discord_invites (
  platform TEXT NOT NULL,
  user_github_id INTEGER NOT NULL,
  code TEXT NOT NULL,
  url TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY(platform, user_github_id),
  UNIQUE(code),
  FOREIGN KEY(platform, user_github_id) REFERENCES users(platform, github_id)
);

-- @owner community
CREATE TABLE IF NOT EXISTS discord_sync_jobs (
  platform TEXT NOT NULL,
  user_github_id INTEGER NOT NULL,
  action_kind TEXT NOT NULL,
  discord_user_id TEXT NOT NULL,
  discord_username TEXT,
  access_token TEXT,
  welcome_channel_id TEXT,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  synced_at TEXT,
  PRIMARY KEY(platform, user_github_id, action_kind),
  FOREIGN KEY(platform, user_github_id) REFERENCES users(platform, github_id)
);

-- @owner packages
-- @readers operations
CREATE TABLE IF NOT EXISTS package_crawl_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  period_start TEXT NOT NULL,
  ecosystem TEXT,
  status TEXT NOT NULL,
  refresh INTEGER NOT NULL DEFAULT 0,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  error TEXT,
  updated_at TEXT NOT NULL
);

-- @owner publication
CREATE TABLE IF NOT EXISTS public_snapshot_publications (
  period_start TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  previous_period_start TEXT,
  staged_at TEXT,
  verified_at TEXT,
  published_at TEXT,
  rolled_back_at TEXT,
  backup_path TEXT,
  error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- @owner publication
CREATE TABLE IF NOT EXISTS published_badges (
  period_start TEXT NOT NULL,
  badge_kind TEXT NOT NULL,
  platform TEXT NOT NULL,
  subject_github_id INTEGER NOT NULL,
  label TEXT NOT NULL,
  status TEXT NOT NULL,
  rank INTEGER,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(period_start, badge_kind, platform, subject_github_id)
);

-- @owner packages
-- @readers operations
CREATE TABLE IF NOT EXISTS package_repository_scans (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  period_start TEXT NOT NULL,
  repository_kind TEXT NOT NULL,
  platform TEXT NOT NULL,
  repository_source_id INTEGER NOT NULL,
  full_name TEXT NOT NULL,
  default_branch TEXT,
  tree_sha TEXT,
  tree_truncated INTEGER NOT NULL DEFAULT 0,
  manifest_count INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending',
  error TEXT,
  checked_at TEXT,
  updated_at TEXT NOT NULL,
  UNIQUE(period_start, repository_kind, platform, repository_source_id)
);

-- @owner packages
-- @readers operations
CREATE TABLE IF NOT EXISTS package_manifests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  repository_scan_id INTEGER NOT NULL,
  ecosystem TEXT NOT NULL,
  path TEXT NOT NULL,
  blob_sha TEXT,
  package_name TEXT,
  normalized_package_name TEXT,
  private_package INTEGER NOT NULL DEFAULT 0,
  custom_registry TEXT,
  repository_url TEXT,
  homepage_url TEXT,
  license TEXT,
  confidence TEXT NOT NULL,
  parse_status TEXT NOT NULL,
  parser_version TEXT NOT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  parsed_at TEXT NOT NULL,
  UNIQUE(repository_scan_id, ecosystem, path),
  FOREIGN KEY(repository_scan_id) REFERENCES package_repository_scans(id)
);

-- @owner packages
-- @readers operations
CREATE TABLE IF NOT EXISTS registry_packages (
  ecosystem TEXT NOT NULL,
  package_name TEXT NOT NULL,
  normalized_package_name TEXT NOT NULL,
  registry_url TEXT NOT NULL,
  repository_url TEXT,
  homepage_url TEXT,
  license TEXT,
  latest_version TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  error TEXT,
  checked_at TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(ecosystem, normalized_package_name)
);

-- @owner packages
CREATE TABLE IF NOT EXISTS registry_package_links (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  manifest_id INTEGER NOT NULL,
  ecosystem TEXT NOT NULL,
  normalized_package_name TEXT NOT NULL,
  match_confidence TEXT NOT NULL,
  matched INTEGER NOT NULL DEFAULT 0,
  checked_at TEXT,
  UNIQUE(manifest_id, ecosystem, normalized_package_name),
  FOREIGN KEY(manifest_id) REFERENCES package_manifests(id),
  FOREIGN KEY(ecosystem, normalized_package_name)
    REFERENCES registry_packages(ecosystem, normalized_package_name)
);

-- @owner packages
-- @readers operations
CREATE TABLE IF NOT EXISTS registry_package_snapshots (
  ecosystem TEXT NOT NULL,
  normalized_package_name TEXT NOT NULL,
  period_start TEXT NOT NULL,
  downloads_total INTEGER,
  downloads_30d INTEGER,
  downloads_7d INTEGER,
  dependents_count INTEGER,
  dependent_repositories_count INTEGER,
  latest_version TEXT,
  latest_release_at TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  observed_at TEXT NOT NULL,
  PRIMARY KEY(ecosystem, normalized_package_name, period_start),
  FOREIGN KEY(ecosystem, normalized_package_name)
    REFERENCES registry_packages(ecosystem, normalized_package_name)
);

CREATE INDEX IF NOT EXISTS idx_user_stats_period_country_total
  ON user_monthly_stats(period_start, country, total_stars, platform);
CREATE INDEX IF NOT EXISTS idx_user_stats_period_city_delta
  ON user_monthly_stats(period_start, city, monthly_stars_delta, platform);
CREATE INDEX IF NOT EXISTS idx_candidate_users_period_platform_status_login
  ON candidate_users(period_start, platform, status, login);
CREATE INDEX IF NOT EXISTS idx_candidate_organizations_period_platform_status_login
  ON candidate_organizations(period_start, platform, status, login);
CREATE INDEX IF NOT EXISTS idx_crawl_job_runs_status_command_started
  ON crawl_job_runs(status, command, started_at);
CREATE INDEX IF NOT EXISTS idx_repo_stats_period_country_total
  ON repository_monthly_stats(period_start, owner_country, stargazers_count, platform);
CREATE INDEX IF NOT EXISTS idx_repo_stats_period_city_delta
  ON repository_monthly_stats(period_start, owner_city, monthly_stars_delta, platform);
CREATE INDEX IF NOT EXISTS idx_repo_stats_period_platform_owner
  ON repository_monthly_stats(period_start, platform, owner_github_id);
CREATE INDEX IF NOT EXISTS idx_org_stats_period_country_total
  ON organization_monthly_stats(period_start, country, total_stars, platform);
CREATE INDEX IF NOT EXISTS idx_org_stats_period_country_delta
  ON organization_monthly_stats(period_start, country, monthly_stars_delta, platform);
CREATE INDEX IF NOT EXISTS idx_org_repo_stats_period_country_total
  ON organization_repository_monthly_stats(period_start, organization_country, stargazers_count, platform);
CREATE INDEX IF NOT EXISTS idx_org_repo_stats_period_country_delta
  ON organization_repository_monthly_stats(period_start, organization_country, monthly_stars_delta, platform);
CREATE INDEX IF NOT EXISTS idx_org_repo_stats_period_platform_owner
  ON organization_repository_monthly_stats(period_start, platform, organization_github_id);
CREATE INDEX IF NOT EXISTS idx_repo_star_observations_repo_period
  ON repository_star_observations(platform, repository_github_id, period_start);
CREATE INDEX IF NOT EXISTS idx_org_repo_star_observations_repo_period
  ON organization_repository_star_observations(platform, repository_github_id, period_start);
CREATE INDEX IF NOT EXISTS idx_api_request_events_recorded_platform
  ON api_request_events(recorded_at, platform);

CREATE INDEX IF NOT EXISTS idx_job_work_events_period_kind_stage
  ON job_work_events(period_start, job_kind, stage, unit_kind, platform, ecosystem);

CREATE INDEX IF NOT EXISTS idx_job_work_events_finished_at
  ON job_work_events(finished_at);
CREATE INDEX IF NOT EXISTS idx_discord_connections_user
  ON discord_connections(platform, user_github_id);
CREATE INDEX IF NOT EXISTS idx_published_badges_identity
  ON published_badges(badge_kind, platform, subject_github_id, period_start);
CREATE INDEX IF NOT EXISTS idx_package_repository_scans_status_period
  ON package_repository_scans(period_start, status, repository_kind, platform);
CREATE INDEX IF NOT EXISTS idx_package_manifests_ecosystem_name
  ON package_manifests(ecosystem, normalized_package_name);
CREATE INDEX IF NOT EXISTS idx_registry_package_links_lookup
  ON registry_package_links(ecosystem, normalized_package_name, matched, manifest_id);
CREATE INDEX IF NOT EXISTS idx_registry_package_snapshots_ecosystem_downloads
  ON registry_package_snapshots(period_start, ecosystem, downloads_30d, downloads_total);
CREATE INDEX IF NOT EXISTS idx_registry_package_snapshots_ecosystem_dependents
  ON registry_package_snapshots(period_start, ecosystem, dependents_count);

INSERT OR IGNORE INTO repository_star_observations(
  period_start, platform, repository_github_id, stargazers_count, observed_at
)
SELECT period_start, platform, repository_github_id, stargazers_count, updated_at
FROM repository_monthly_stats;

INSERT OR IGNORE INTO organization_repository_star_observations(
  period_start, platform, repository_github_id, stargazers_count, observed_at
)
SELECT period_start, platform, repository_github_id, stargazers_count, updated_at
FROM organization_repository_monthly_stats;
