# Project Overview

Polish Open Source Rank is a monthly Ruby application that builds public
rankings for users, repositories, organizations, and packages connected to
Poland and selected Polish cities.

Public platform APIs do not expose a portable location-regex search, so the
monthly sync searches a fixed catalog of country and city variants, stores
candidates, and then classifies profiles locally. Interrupted runs are
resumable because candidates and monthly snapshots are stored in SQLite.

Package rankings run after the monthly source ranking. The package job scans
already ranked public repositories for known manifest files, resolves package
identities through registry APIs, and stores registry snapshots in the same
SQLite database.

## Collected Data

- User login, name, raw location, normalized city, normalized country, public
  email, homepage, profile URL, and avatar URL.
- User monthly stats: public repository count, total stars across owned public
  repositories, stars gained during the month when the platform exposes dated
  star history, and public activity event count for the month.
- Repository data per user: name, full name, URL, homepage, language,
  description, and fork/archive flags.
- Repository monthly stats: stars and stars gained during the month.
- Organization profiles and organization repositories with the same public
  ranking fields.
- Package manifest data from public repositories: ecosystem, manifest path,
  package name, normalized package name, parser status, registry links,
  homepage, repository URL, and license when the manifest exposes it.
- Package registry snapshots: latest version, release timestamp when available,
  download metrics when available, dependent package counts when available, and
  dependent repository counts when available.

## Rankings

Each scope includes:

- Top 10 users by total stars.
- Trending 10 users by stars gained in the month.
- Top 10 active users by public platform events in the month.
- Top 10 repositories by stars.
- Trending 10 repositories by stars gained in the month.
- Top 10 organizations and organization repositories.
- Package rankings per ecosystem by 30-day downloads, total downloads, and
  dependent package count when those metrics exist.

Scopes include Poland plus supported Polish cities. Package rankings are
country-level only and are not split by city.
