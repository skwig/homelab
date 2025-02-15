# 🏠 homelab
Currently running on a single Raspberry Pi 4B K3S instance.
Planning on migrating to a multiple node NUC cluster running Talos Linux.

```sh
pi@raspberrypi:~ $ neofetch
       _,met$$$$$gg.          pi@raspberrypi
    ,g$$$$$$$$$$$$$$$P.       --------------
  ,g$$P"     """Y$$.".        OS: Debian GNU/Linux 11 (bullseye) aarch64
 ,$$P'              `$$$.     Host: Raspberry Pi 4 Model B Rev 1.5
',$$P       ,ggs.     `$$b:   Kernel: 5.15.32-v8+
`d$$'     ,$P"'   .    $$$    Uptime: 251 days, 22 hours, 1 min
 $$P      d$'     ,    $$P    Packages: 650 (dpkg)
 $$:      $$.   -    ,d$$'    Shell: bash 5.1.4
 $$;      Y$b._   _,d$P'      Terminal: /dev/pts/0
 Y$$.    `.`"Y$$$$P"'         CPU: BCM2835 (4) @ 1.800GHz
 `$$b      "-.__              Memory: 2554MiB / 3794MiB
  `Y$$
   `Y$$.
     `$$b.
       `Y$$b.
          `"Y$b._
              `"""
```

## Bootstrapping

```
curl -sfL https://get.k3s.io | sh -
flux bootstrap github --owner skwig --repository homelab --branch master --path clusters/production --personal
kubectl create secret generic azure-credentials --from-literal=ClientID="$(terraform output -raw client_id)" --from-literal=ClientSecret="$(terraform output -raw client_secret)" -n external-secrets
```
