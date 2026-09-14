alias fmt := format
alias f := format

format:
    treefmt --no-cache .

sops-decrypt:
    sops decrypt talos/secrets.sops.yaml > talos/secrets.yaml
    sops decrypt talos/controlplane.sops.yaml > talos/controlplane.yaml
    sops decrypt talos/worker.sops.yaml > talos/worker.yaml
    sops decrypt talos/talosconfig.sops.yaml > talos/talosconfig

sops-encrypt:
    sops encrypt talos/secrets.yaml > talos/secrets.sops.yaml
    sops encrypt talos/controlplane.yaml > talos/controlplane.sops.yaml
    sops encrypt talos/worker.yaml > talos/worker.sops.yaml
    sops encrypt --input-type yaml --output-type yaml talos/talosconfig > talos/talosconfig.sops.yaml

talosconfig-gen:
    test -n "$TALOSCONFIG"
    talosctl gen config homelab https://homelab.nidus:6443 --with-secrets talos/secrets.yaml --output-types talosconfig --output "$TALOSCONFIG" --force >/dev/null
    talosctl config endpoint homelab.nidus
    talosctl config node homelab.nidus

kubeconfig-gen:
    talosctl kubeconfig --force
