# n8n — self-hosted Kubernetes (ClickOps-first draft)

This is a **reusable n8n instance**, namespace `n8n`, in the existing homelab Flux/Kustomize
style. The initial deployment contains **no automation workflows**: explore the n8n UI first.
This is a draft to copy into your repo, not a committed change.

## Resources

- `n8n` Deployment (one replica) + ClusterIP Service + private nginx TLS Ingress
- `n8n-db` CloudNativePG Cluster (one instance) on `local-path-retain`
- `n8n-data` PVC for `/home/node/.n8n`
- Two `ExternalSecret` resources pulling three values from Azure Key Vault
- Optional Signal sender as `signal/` folder (OFF by default)
- No Ollama, finance, Google or Signal credentials in public Git

## Step 1 — create three Azure Key Vault secrets

| Key Vault secret name | Value | Note |
| --- | --- | --- |
| `n8n-encryption-key` | long random string, >=32 bytes entropy | Keep permanently; backup securely. |
| `n8n-db-username` | `n8n` | Must match CloudNativePG database owner. |
| `n8n-db-password` | separate strong random password | Keep in Key Vault. |

Example ways to generate values *locally*: `openssl rand -base64 48` (each key/password separately).
**Do not paste the generated values in Git, terminal transcripts, or exported workflow JSON.**
`n8n-encryption-key` is essential for decrypting n8n credentials after restore. CNPG will
also manage some internal PostgreSQL secrets; this setup sources the *application* DB
credential from Key Vault. Google OAuth refresh tokens you create in the n8n UI reside
encrypted in n8n's PostgreSQL data — not solely in Key Vault.

## Step 2 — review and enable in production

1. Copy `kubernetes/apps/base/n8n/` from this draft to your repository.
2. Verify the existing ingress class, `cert-manager` issuer, private DNS target,
   `local-path-retain` StorageClass, CloudNativePG CRD and
   `azure-kv-cluster-secret-store` ClusterSecretStore. **The private IP and issuer here
   were carried over from the earlier homelab scaffold, not freshly cluster-tested.**
3. Edit your **existing** `kubernetes/apps/overlays/production/kustomization.yaml` and add
   `- ../../base/n8n/` under `resources:`. Do not replace the rest of the file.
4. Check manifests locally:

   ```bash
   kubectl kustomize kubernetes/apps/base/n8n
   kubectl kustomize kubernetes/apps/overlays/production >/tmp/homelab-rendered.yaml
   ```

5. Commit and let Flux reconcile. Check:

   ```bash
   kubectl -n n8n get externalsecret,secret,pvc,pod,deploy,svc,ingress
   kubectl -n n8n get cluster.postgresql.cnpg.io n8n-db
   kubectl -n n8n describe externalsecret n8n-db-credentials
   kubectl -n n8n logs deploy/n8n --tail=80
   ```

   Avoid dumping Secret values or sensitive logs into public issues.
6. Open `https://n8n.skwig.party` over your **LAN/VPN**, create the n8n owner account.
7. In the UI, create `Manual Trigger → Edit Fields (Set)` and execute it. No external
   account is required for this smoke test. Later manually add OAuth credentials.

## Step 3 — manual workflows first

- Start with `Manual Trigger → HTTP Request` against a harmless test endpoint or your
  own internal service. Then add `Schedule Trigger` at `0 7 * * 1` (Europe/Bratislava).
- After basic UI navigation, optionally add the Signal sender below and test it.
- Next connect Google Calendar, then Gmail. Keep financial-provider integrations out of the
  public workflow exports unless carefully abstracted and reviewed.
- Ollama stays on desktop GPU. You can later use its private HTTP endpoint in an n8n
  Ollama credential/node. Monday 07:00 delivery should never depend on live GPU access.

`automations/README.md` explains how to manually export sanitized human-readable JSON
into the public repository **after** you have learned the UI. Nothing auto-imports and
nothing auto-exports during this initial phase.

## Optional — Signal sender

Enable by uncommenting/adding `- signal/` in
`kubernetes/apps/base/n8n/kustomization.yaml`, then commit. This deploys
`signal-api` as a private ClusterIP Service plus PVC; no public ingress.

On a workstation that can access Kubernetes, link it as a Signal secondary device:

```bash
kubectl -n n8n port-forward service/signal-api 8080:8080
```

Open `http://localhost:8080/v1/qrcodelink?device_name=homelab-automation` in your browser;
in Signal Android use **Settings → Linked devices → Link new device** to scan.
If a NetworkPolicy prevents port-forward access in your CNI, temporarily disable the
policy just for linking and re-enable it immediately afterward. The underlying Signal
service is an **unofficial** client and must be kept updated.

Once linked, n8n HTTP Request can POST to:
`http://signal-api.n8n.svc.cluster.local:8080/v2/send` with JSON body:
`{ "message": "test", "number": "<sender>", "recipients": ["<recipient>"] }`.
Do not commit actual sender/recipient numbers to workflow JSON. For Note to Self,
verify that Android actually raises a notification; self-messages can behave differently.

## Safeguards / limitations

- `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` blocks env access in expressions/Code nodes; it is
  not a hard security boundary against a fully compromised n8n container.
- Successful, failed and manual execution payload persistence is disabled to reduce
  retained PII. This makes troubleshooting harder. The database **still contains**
  workflows and encrypted credentials; data in other stores can remain plaintext.
- `local-path-retain` is **not automatically encrypted**. Protect underlying volumes,
  and configure *encrypted, versioned and tested backups* of PostgreSQL, the n8n PVC,
  Signal state (if enabled), and the stable encryption key before real mail/finance data.
- No external auth proxy / NetworkPolicy for n8n editor is added. Keep the ingress
  private and protect it with a strong owner login; do not expose it to the WAN.
- This draft assumes a single Talos node and no high availability. One n8n instance is
  enough for many workflows. The PostgreSQL database is for **n8n internal state**;
  use a separate app database for future timeline/invoice records.
- Google OAuth callbacks need browser access to the same private ingress hostname:
  `https://n8n.skwig.party/rest/oauth2-credential/callback`.
- Image tags are pinned at drafting time (`n8n:2.44.5` stable and Signal `0.101`).
  Review release notes and upgrade intentionally. Verify CNPG PostgreSQL image version
  against the operator in your cluster.
- Flux will revert changes to managed Kubernetes resources. "ClickOps" here means
  **editing workflows and credentials in the n8n UI**, not editing GitOps infrastructure
  through the Kubernetes dashboard.
