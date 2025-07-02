```sh
talosctl gen config homelab https://homelab.nidus:6443
talosctl apply-config --nodes homelab.nidus --file controlplane.yaml --insecure
talosctl bootstrap --nodes homelab.nidus --endpoints homelab.nidus --talosconfig=./talosconfig
talosctl kubeconfig --nodes homelab.nidus --endpoints homelab.nidus --talosconfig=./talosconfig
```
