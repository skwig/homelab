sops encrypt talos/secrets.yaml > talos/secrets.sops.yaml
sops encrypt talos/controlplane.yaml > talos/controlplane.sops.yaml
sops encrypt talos/worker.yaml > talos/worker.sops.yaml
sops encrypt --output-type yaml talos/talosconfig > talos/talosconfig.sops.yaml
