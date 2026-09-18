# 🏠 homelab

## Production env

Currently running on a single instance running Talos.
Reconciles `kubernetes/clusters/production`.

```sh
Host: ThinkCentre M910q
CPU: Intel(R) Core(TM) i5-6500T (4) @ 3.10 GHz
GPU: Intel HD Graphics 530 @ 1.10 GHz [Integrated]
Memory: 15.51 GiB
Disk: 1000 GiB
```

### Getting started

1. Apply [OpenTofu](https://opentofu.org/) from [iac](./iac/)
2. Install [Talos Linux](https://www.talos.dev/) from [talos](./talos/)
3. Create a secret to access Azure based on OpenTofu output
   ```sh
   kubectl create namespace "external-secrets"
   kubectl create secret generic azure-credentials --from-literal=ClientID="$(tofu output -raw client_id)" --from-literal=ClientSecret="$(tofu output -raw client_secret)" -n "external-secrets"
   ```
4. Generate a finegrained PAT exclusive to this repo with permissions listed [here](https://fluxcd.io/flux/installation/bootstrap/github/#github-organization)
5. Install [Flux](https://fluxcd.io/)
   ```sh
   flux install
   flux bootstrap github --owner skwig --repository homelab --branch master --path ./kubernetes/clusters/production --personal
   ```

## Dev env

Disposable cluster with [Kind](https://kind.sigs.k8s.io/), Flux, and a local OCI registry.
Reconciles `kubernetes/clusters/dev` from a snapshot of the current working tree, including uncommitted and untracked non-ignored files.

See `just dev` for commands.

Runtime files live at `kind.dev.yaml`, `compose.dev.yaml`, and `dev.just`. The default state directory is `$XDG_CACHE_HOME/homelab-dev`.

## Storage classes

- `local-path-*` - Used when storage cannot be over the network (e.g. postgres)
- `nfs-share-*` - Used when storage is on NAS, but can be accessed WITHOUT authentication
- `smb-share-*` - Used when storage is on NAS, but should be accessed WITH authentication
- `null` - Used when statically provisioning `PersistentVolume` with a specific driver
