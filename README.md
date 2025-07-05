# 🏠 homelab
Currently running on a single instance running Talos.

```sh
Host: ThinkCentre M910q
CPU: Intel(R) Core(TM) i5-6500T (4) @ 3.10 GHz
GPU: Intel HD Graphics 530 @ 1.10 GHz [Integrated]
Memory: 15.51 GiB
Disk: 1000 GiB
```

## Getting started

1. Apply [OpenTofu](https://opentofu.org/) from [iac](./iac/)
2. Install [Talos Linux](https://www.talos.dev/) from [talos](./talos/)
3. Create a secret to access Azure based on OpenTofu output
    ```sh
    kubectl create namespace "external-secrets"
    kubectl create secret generic azure-credentials --from-literal=ClientID="$(tofu output -raw client_id)" --from-literal=ClientSecret="$(tofu output -raw client_secret)" -n "external-secrets"
    ```
4. Generate a finegrained PAT exclusive to this repo with permissions listed [here](https://fluxcd.io/flux/installation/bootstrap/github/#github-organization)
4. Install [Flux](https://fluxcd.io/)
    ```sh
    flux install
    flux bootstrap github --owner skwig --repository homelab --branch master --path ./kubernetes/clusters/production --personal
    ```
