# Media automation

Seerr handles movie and TV requests. Radarr manages movies, Sonarr manages series,
Prowlarr manages their indexers, and qBittorrent downloads the selected releases.
Radarr/Sonarr import completed downloads into the library, Jellyfin serves it, and
Bazarr adds subtitles.

Flux reconciles this directory through `app-arr`. The manifests deploy the
applications; configure their connections and preferences through their UIs in
the order below. Passwords, API keys, indexer credentials, quality profiles, and
request permissions are not supplied by these manifests.

## Access

Only Seerr and Jellyfin have ingress URLs. The other UIs are available through
port-forwarding; all application-to-application traffic uses internal service DNS.

| Application | Internal URL                                      | Browser access                           |
| ----------- | ------------------------------------------------- | ---------------------------------------- |
| Seerr       | `http://seerr.arr.svc.cluster.local:5055`         | `https://seerr.skwig.party`              |
| Jellyfin    | `http://jellyfin.jellyfin.svc.cluster.local:8096` | `https://jellyfin.skwig.party`           |
| qBittorrent | `http://qbittorrent.arr.svc.cluster.local:8080`   | `http://localhost:8080` via port-forward |
| Radarr      | `http://radarr.arr.svc.cluster.local:7878`        | `http://localhost:7878` via port-forward |
| Sonarr      | `http://sonarr.arr.svc.cluster.local:8989`        | `http://localhost:8989` via port-forward |
| Prowlarr    | `http://prowlarr.arr.svc.cluster.local:9696`      | `http://localhost:9696` via port-forward |
| Bazarr      | `http://bazarr.arr.svc.cluster.local:6767`        | `http://localhost:6767` via port-forward |

Select the intended Kubernetes context first. Run each needed command in a
separate terminal and leave it running while using that UI:

```sh
kubectl -n arr port-forward svc/qbittorrent 8080:8080
kubectl -n arr port-forward svc/radarr 7878:7878
kubectl -n arr port-forward svc/sonarr 8989:8989
kubectl -n arr port-forward svc/prowlarr 9696:9696
kubectl -n arr port-forward svc/bazarr 6767:6767
```

The default listener is localhost. Use the internal URLs from the table when
connecting applications: `localhost` inside a container refers to that container's
pod, not another service or your workstation.

After reconciliation, update Jellyfin clients and bookmarks from
`jellyfin.homelab.skwig.party` to `jellyfin.skwig.party`. qBittorrent's former
`qbit.skwig.party` ingress is removed by Flux pruning; use port-forwarding instead.
DNS/TLS use the existing nginx, cert-manager, and external-dns configuration.

## Storage

Radarr, Sonarr, Bazarr, and qBittorrent mount the existing
`qbittorrent-downloads` NFS claim at `/downloads`. This maps the root of the NAS
`Media_Shared` share:

| NAS directory | Container path           | Purpose                         |
| ------------- | ------------------------ | ------------------------------- |
| `.InProgress` | `/downloads/.InProgress` | Incomplete downloads            |
| `Downloads`   | `/downloads/Downloads`   | Completed downloads and seeding |
| `Movies`      | `/downloads/Movies`      | Movie library and subtitles     |
| `Series`      | `/downloads/Series`      | Series library and subtitles    |

Media-writing applications use UID/GID `1000`. The NAS must grant this identity
write access to the relevant directories. Mounting one share at one path allows
hardlinks between downloads and libraries when the NAS filesystem supports them;
separate filesystems or restrictive ACLs can still prevent them. No remote path
mappings are needed. Jellyfin keeps its existing read-only SMB media mount and
library paths; its container paths need not match the automation apps' paths.

Each application has a dedicated local configuration PVC:

- `qbittorrent-config`, `radarr-config`, `sonarr-config`, `prowlarr-config`, and
  `bazarr-config` mount at `/config` in their respective containers.
- `seerr-config` mounts at `/app/config`.

These claims request `1Gi` from `local-path-retain`. They store SQLite databases,
settings, credentials, history, and caches. Seerr and Prowlarr have no media mount.
Local state survives pod replacement but is tied to the node's storage. PVC
retention is not a backup, and local-path requested capacity is not a disk quota.
Monitor node free space and copy supported application backups off-node to the
NAS. This directory does not automate backups. Use application backup tools or
stop the application before copying live database state.

### qBittorrent configuration persistence

`qBittorrent.conf` in this directory supplies **first-start defaults**. An init
container copies it onto `qbittorrent-config` only if the persisted file is
missing or empty. A nonempty configuration and existing torrent state are
preserved. The running application uses a writable configuration file, so UI
passwords and other settings can persist.

Editing the tracked defaults does not overwrite an initialized installation.
Manage an existing installation's settings in its UI. After upgrading from the
old read-only ConfigMap mount, verify the save paths below and set a persistent
password before connecting Radarr/Sonarr. Do not delete the PVC to reset settings.

## Initial setup

### 1. Check readiness and authenticate

After deploying through the normal Flux workflow:

```sh
kubectl -n arr get pods,pvc,svc,ingress
```

Expect all six applications to become ready, local configuration claims to bind,
and only `seerr` to appear as an ingress in this namespace. Jellyfin is in the
`jellyfin` namespace. Complete each application's initial authentication setup
through its UI. Keep API keys and passwords in application settings rather than
committing them to Git.

### 2. Verify NAS permissions and hardlinks

The existing `Downloads`, `Movies`, and `Series` directories must be writable by
UID/GID 1000. This check runs as LinuxServer's application user, creates an empty
temporary file, links it into both library directories, reports inode/link
counts, and cleans up its own files:

```sh
kubectl -n arr exec deployment/radarr -- s6-setuidgid abc sh -eu -c '
  source_file=$(mktemp /downloads/Downloads/.arr-hardlink-check.XXXXXX)
  basename=${source_file##*/}
  movie_file=/downloads/Movies/$basename
  series_file=/downloads/Series/$basename
  trap '\''rm -f "$source_file" "$movie_file" "$series_file"'\'' EXIT
  id
  ln "$source_file" "$movie_file"
  ln "$source_file" "$series_file"
  stat -c "%d:%i %h %n" "$source_file" "$movie_file" "$series_file"
'
```

Expect the three files to share a device/inode and have a link count of `3`.
If it fails, check NAS ACLs, ownership, and filesystem boundaries. Avoid recursive
permission changes across the whole share. Imports can fall back to copying if
hardlinks are unavailable, using additional disk space while torrents seed.

### 3. Configure qBittorrent

1. Log in through its port-forward. On a fresh configuration, the temporary admin
   password is reported in the pod logs; set your own password in the UI.
2. Verify the default save path is `/downloads/Downloads`, and incomplete
   downloads use `/downloads/.InProgress`.
3. Create the category `radarr` with save path
   `/downloads/Downloads/radarr`, and `sonarr` with save path
   `/downloads/Downloads/sonarr`.
4. Confirm the password, category settings, and active torrent state survive a
   controlled restart before relying on automated downloads. Do not recategorize
   existing torrents unless you intend to change how they are managed.

qBittorrent continues using its direct internet connection.

### 4. Configure Radarr and Sonarr

| Setting              | Radarr                              | Sonarr                              |
| -------------------- | ----------------------------------- | ----------------------------------- |
| Root folder          | `/downloads/Movies`                 | `/downloads/Series`                 |
| Download client type | qBittorrent                         | qBittorrent                         |
| Download client host | `qbittorrent.arr.svc.cluster.local` | `qbittorrent.arr.svc.cluster.local` |
| Download client port | `8080`                              | `8080`                              |
| Download client SSL  | Off (internal HTTP)                 | Off (internal HTTP)                 |
| Category             | `radarr`                            | `sonarr`                            |

Supply the qBittorrent credentials and use the download client's **Test** button
before saving. Enable completed-download handling and **Use Hardlinks instead of
Copy** in advanced Media Management settings. Leave remote path mappings empty.
Choose quality profiles and seeding/removal policies in the UI; do not remove
torrents before their seeding requirements are met.

Use each application's library import to bring existing organized Movies/Series
under management. Review matches and monitoring choices before enabling searches
for missing media. The manifests do not move or rename existing files.

### 5. Configure Prowlarr

1. Add your indexers and their credentials, testing each connection.
2. Under Settings → Apps, add Radarr and Sonarr using their internal URLs from
   the table and their API keys (available in each application's General settings).
3. Set the Prowlarr server URL to
   `http://prowlarr.arr.svc.cluster.local:9696` so synced indexers call back to the
   correct address.
4. Test and sync the integrations. **Full Sync** makes Prowlarr authoritative for
   synced indexer settings; manage those settings in Prowlarr.

Radarr/Sonarr submit downloads to qBittorrent. Prowlarr does not need its own
download client for that workflow.

### 6. Configure Bazarr

Enable the Radarr and Sonarr integrations with their internal service hosts,
ports, and API keys. Paths already match, so leave path mappings empty. Select
subtitle providers, supply any required credentials, and create language profiles
and assign them to movies/series. Bazarr writes subtitle files beside the media
in `Movies` and `Series`.

### 7. Configure Seerr and Jellyfin

1. Open `https://seerr.skwig.party` and connect Jellyfin at
   `http://jellyfin.jellyfin.svc.cluster.local:8096` during setup.
2. Set the browser-facing Jellyfin/external URL to
   `https://jellyfin.skwig.party`, keeping the internal connection URL separate.
3. Select the Jellyfin libraries to sync and import the desired users.
4. Add Radarr and Sonarr with their internal service URLs and API keys. Mark the
   intended servers as default, select the movie/series root folders and quality
   profiles, and configure request permissions and approval policy.
5. Keep Jellyfin's existing Movies/Series library folders. Verify newly imported
   media is discovered; SMB filesystem notifications may require scheduled or
   manual library scans.

Validate one movie or episode request end-to-end: request → approval → search →
download → library import → Jellyfin scan → playback. Verify qBittorrent can
continue seeding the download after import, and check a subtitle download in
Bazarr. Seerr handles requests, but quality settings, indexers, and troubleshooting
still live in the individual applications.

## Troubleshooting

```sh
kubectl -n arr get pods,pvc,svc,ingress
kubectl -n arr get events --sort-by=.lastTimestamp
kubectl -n arr logs deployment/radarr --tail=100
kubectl -n arr logs deployment/seerr --tail=100
kubectl -n arr logs deployment/qbittorrent -c seed-config
kubectl -n arr describe pod -l app.kubernetes.io/name=seerr
```

- **Pending PVC/pod:** inspect events and `local-path-retain` provisioning. Local
  claims bind to the node where they are provisioned; a lost node is not automatic
  failover. For media mount failures, check NFS CSI and NAS reachability.
- **qBittorrent initializer fails:** inspect its logs and ensure UID/GID 1000 can
  write its existing config directory. The initializer preserves nonempty files;
  it does not reset credentials.
- **Connection tests fail:** confirm service DNS, port, API key or credentials,
  and that the destination pod is ready. Keep internal connections on HTTP and
  URL bases empty unless deliberately configured otherwise.
- **Download completes but import fails:** check the matching category, reported
  download path, UID/GID permissions, free space, and the application's activity
  queue/history. Avoid moving active torrent data to solve a path mismatch.
- **Library is missing in Jellyfin:** confirm the Movies/Series paths and run a
  library scan. Jellyfin reads the NAS over SMB; the importers write over NFS.
- **Pod becomes unready:** inspect its logs. Radarr, Sonarr, and Prowlarr probe
  `/ping`; Seerr probes `/api/v1/settings/public`. Bazarr uses TCP probes because
  its UI can return HTTP 401 when Basic authentication is enabled. Probes do not
  depend on other applications being online.

## Local validation and development

```sh
kustomize build kubernetes/apps/base/arr
kustomize build kubernetes/apps/base/jellyfin
kustomize build kubernetes/apps/base/homepage
kustomize build kubernetes/clusters/production
kustomize build kubernetes/clusters/dev
```

The development overlay redirects `qbittorrent-downloads-pv` to the development
NFS server. All media consumers reuse that claim. With the disposable
`kind-homelab-dev` cluster running, `just dev sync` publishes the working tree and
reconciles it. Check readiness with an explicit context:

```sh
kubectl --context kind-homelab-dev -n arr get pods,pvc,svc,ingress
```

Rendering validates manifest composition, not NAS permissions, application
credentials, DNS reachability, or the complete request/download/import workflow.
Verify those after deployment using the setup steps above.
