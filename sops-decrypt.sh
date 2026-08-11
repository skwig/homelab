sops decrypt talos/secrets.sops.yaml >talos/secrets.yaml
sops decrypt talos/controlplane.sops.yaml >talos/controlplane.yaml
sops decrypt talos/worker.sops.yaml >talos/worker.yaml
sops decrypt talos/talosconfig.sops.yaml >talos/talosconfig
