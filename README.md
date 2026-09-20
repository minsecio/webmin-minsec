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

## Safe configuration writes

Structured settings are written only to `conf.d/webmin.toml`. Filter overrides are written to `conf.d/webmin-filter-NAME.toml`. Raw editing is restricted to files reported by `inspect` or validated `.toml` names directly below `conf.d` and `filters`.

Every save or delete copies the complete configuration tree to a private temporary directory, applies the candidate change, runs `check --all`, and atomically changes the live file only after validation succeeds. Symbolic links and traversal are rejected. A restart occurs only when the user chooses **Save and Restart** and validation succeeded.

## Installation

Download the `webmin-minsec` deb or RPM from the [releases page](https://github.com/minsecio/webmin-minsec/releases) and install it with `apt` or `dnf`. Webmin must already be installed. Alternatively, copy this directory into Webmin's module directory as `minsec`. Defaults target `/usr/bin/minsec`, `/etc/minsec`, the `minsec` service, and `/usr/sbin/nft`; all are configurable in Module Config.

## Releasing

Set `version=` in `module.info`, commit, and push a matching tag such as `v0.1.0`. The release workflow checks out Webmin's `makemodulerpm.pl` and `makemoduledeb.pl`, builds both packages, installs them on top of Webmin in AlmaLinux, Debian, and Ubuntu containers, and attaches them to a GitHub release. Files listed in `EXCLUDE` are left out of the packages.

## Tests

```sh
MINSEC_TESTING=1 prove -v t/lib.t t/commands.t t/socket.t t/perlcritic.t
```

The socket test creates a temporary Unix socket. In a restricted sandbox it may require permission to create local sockets.

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
