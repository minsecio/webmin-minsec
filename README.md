# Minsec Webmin Module

A Linux-only Webmin module for the minsec intrusion-prevention daemon. It provides service status, live ban management, filter policy controls and testing, structured and raw TOML editing, JSONL event history, configuration backups, ACLs, and a read-only view of `table inet minsec`.

## Screenshots

Screenshots use invented data on a private test machine.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://minsecio.github.io/webmin-minsec/dark/01-dashboard.png">
  <img alt="Dashboard: service state, counters and per-filter match and ban totals" src="https://minsecio.github.io/webmin-minsec/light/01-dashboard.png">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://minsecio.github.io/webmin-minsec/dark/02-bans.png">
  <img alt="Active bans with unban and manual ban controls" src="https://minsecio.github.io/webmin-minsec/light/02-bans.png">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://minsecio.github.io/webmin-minsec/dark/04-filter-policy.png">
  <img alt="Filter policy editor with a filter test form" src="https://minsecio.github.io/webmin-minsec/light/04-filter-policy.png">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://minsecio.github.io/webmin-minsec/dark/09-events.png">
  <img alt="Event history" src="https://minsecio.github.io/webmin-minsec/light/09-events.png">
</picture>

## Required minsec machine interface

The module deliberately does not parse minsec configuration itself. It requires these local, offline commands:

- `minsec --config-dir DIR --json inspect` returns one object with `schema_version: 1`, `version`, `paths`, `files`, `filters`, and merged `effective` configuration. Durations in this response are seconds.
- `minsec --config-dir DIR --json check --all` returns one object with `ok`, diagnostics, and the filters checked, including disabled custom filters.
- `minsec --json events --last N` emits one JSON object per line.
- `minsec --json test NAME PATH --quiet` returns one structured filter-test result.
- The path at `inspect.paths.control_socket` accepts the existing newline-delimited JSON requests using `cmd` values `status`, `list`, `ban`, and `unban`.

The inspection schema is treated as a public compatibility interface. Any schema other than version 1 is rejected.

## Safe configuration writes

Structured settings are written only to `conf.d/webmin.toml`. Filter overrides are written to `conf.d/webmin-filter-NAME.toml`. Raw editing is restricted to files reported by `inspect` or validated `.toml` names directly below `conf.d` and `filters`.

Every save or delete copies the complete configuration tree to a private temporary directory, applies the candidate change, runs `check --all`, and atomically changes the live file only after validation succeeds. Symbolic links and traversal are rejected. A restart occurs only when the user chooses **Save and Restart** and validation succeeded.

## Installation

Copy this directory into Webmin's module directory as `minsec`, or package it with Webmin's standard module packaging tools. Defaults target `/usr/bin/minsec`, `/etc/minsec`, the `minsec` service, and `/usr/sbin/nft`; all are configurable in Module Config.

## Tests

```sh
MINSEC_TESTING=1 prove -v t/lib.t t/commands.t t/socket.t t/perlcritic.t
```

The socket test creates a temporary Unix socket. In a restricted sandbox it may require permission to create local sockets.

The companion minsec implementation lives in the separate `minsec` repository. Its Rust tests cover the versioned inspection schema, merged configuration reporting, disabled custom-filter discovery, and structured `check --all` success and error results.

## Regenerating screenshots

The screenshots are generated, not captured by hand. `screenshots/tools/make-shots.sh`
starts a throwaway Webmin on 127.0.0.1:9999 from a private copy of `/etc/webmin`, points
the module at a fake minsec (the real binary reading a generated config tree and event log,
plus a small socket server answering `status` and `list`), and photographs every page in
both Authentic palettes with Playwright. `screenshots/tools/publish.sh` quantizes the result
and force-pushes it as the single commit of the `gh-pages` branch, so the images never enter
the main history.

It needs passwordless sudo, a real `minsec` binary, `npm i --no-save playwright-core`, and a
Playwright Chromium under `~/.cache/ms-playwright`.
