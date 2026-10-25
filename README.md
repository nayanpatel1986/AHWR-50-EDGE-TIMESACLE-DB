# AHWR-50 Twin — TimescaleDB edition

Application source and Windows startup scripts for the AHWR-50 Twin dashboard,
Node.js backend, Python collector, and PostgreSQL/TimescaleDB historian.

## Offline PC: “Access is denied”

Download `support/AHWR-50-STARTUP-CHECK-2026-10-23.zip` and fully extract it.
Copy `Start-AHWR-EDGE.bat` and `Diagnose-AHWR-EDGE-Startup.bat` into the existing
AHWR-EDGE installation folder. Replace only the startup batch file.
Run the diagnostic batch file and review `%TEMP%\AHWR-Startup-Diagnostics.txt`.
See [the diagnostic instructions](STARTUP-HELP-2026-10-23.txt).

The diagnostic checks runtime versions and temporary file write/delete access;
it does not start services or change security policies. If execution is blocked,
ask your IT administrator to review Trend Micro and Windows application-control
events for the exact failing program. Keep endpoint protection enabled.

## Repository contents

- `app/frontend`: React/Vite dashboard source and dependency lockfile.
- `app/backend`: Node.js API, tests, and dependency lockfile.
- `app/shared`, `app/sql`, `app/telegraf`, and `app/collector.py`: shared catalogs,
  database schema, telemetry configuration, and collector.
- Windows launchers, startup scripts, and startup diagnostic patch.

This is a source repository, **not a complete offline installation package**.
Local credentials, saved users, certificates, database records, logs, bundled
runtimes, installed dependencies, and generated frontend files are excluded.
An existing installation should retain its own settings and database.

## Preparing a new installation

On a connected build PC, run `npm ci` in both `app/backend` and `app/frontend`,
then `npm run build` in `app/frontend`. Install the collector dependencies listed
in `app/requirements.txt` into the Python runtime used by the installation.
Supply compatible Windows runtimes at `runtime/node`, `runtime/python`,
`runtime/telegraf`, and `runtime/pgsql` (PostgreSQL with TimescaleDB).
Transfer the prepared dependencies, built frontend, and runtimes to the offline
installation using your organization's approved process.

`Start-AHWR-EDGE.bat` runs `Start-AHWR-EDGE.ps1`, which prompts for initial setup
when `settings.env` is absent. Use unique credentials for each installation.
Application configuration and operational data must be provisioned and reviewed
for the destination rig. The scripts and configuration files document their
required environment variables.
