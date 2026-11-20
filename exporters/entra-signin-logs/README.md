# Entra ID sign-in/audit log exporter

Polls Microsoft Graph every `ENTRA_POLL_INTERVAL_SECONDS` (default 300s) for:

- `/auditLogs/signIns` — sign-ins, MFA, conditional access results
- `/auditLogs/directoryAudits` — admin/directory changes

and pushes each record as a JSON log line to Loki (`job=entra-signin` /
`job=entra-directory-audit`, `platform=m365`).

## One-time setup (Azure portal, do this yourself — not automatable from here)

1. Azure Portal → **Microsoft Entra ID** → **App registrations** → **New registration**.
   Any name, single tenant, no redirect URI needed.
2. Open the new app → **API permissions** → **Add a permission** → **Microsoft Graph**
   → **Application permissions** → add both:
   - `AuditLog.Read.All`
   - `Directory.Read.All`
3. Click **Grant admin consent** for the tenant. Without this step the API
   calls return `403`.
4. **Certificates & secrets** → **New client secret** → copy the secret
   value immediately (shown once).
5. From the app's **Overview** page, copy **Application (client) ID** and
   **Directory (tenant) ID**.
6. Put the three values into `.env`:
   ```
   ENTRA_TENANT_ID=<directory tenant ID>
   ENTRA_CLIENT_ID=<application client ID>
   ENTRA_CLIENT_SECRET=<client secret value>
   ```

## Notes

- Entra ID **Premium P1/P2** is required for the Graph sign-in/audit log
  APIs on most tenants (free/basic tiers have very limited retention and
  may not expose this data via Graph at all) — check your license before
  relying on this.
- First run starts 5 minutes before container start, not from the start of
  the tenant's history — it will not backfill older logs.
- State (last-processed timestamp per source) is kept in the
  `entra_exporter_state` Docker volume. Deleting that volume re-triggers
  the 5-minutes-back start behavior.
