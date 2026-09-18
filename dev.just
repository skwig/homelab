set shell := ["bash", "-euo", "pipefail", "-c"]

set default-list := true

[script]
_snapshot:
    REPO_ROOT="$(git rev-parse --show-toplevel)"
    STATE_DIR="$XDG_CACHE_HOME/homelab-dev"
    worktree="$STATE_DIR/worktree"
    filelist="$STATE_DIR/files.list"

    echo "Creating dev snapshot from the current working tree..." >&2
    rm -rf "$worktree"
    mkdir -p "$worktree"
    mkdir -p "$STATE_DIR"
    git -C "$REPO_ROOT" ls-files -co --exclude-standard -z \
      | while IFS= read -r -d '' path; do
        if [[ -e "$REPO_ROOT/$path" || -L "$REPO_ROOT/$path" ]]; then
          printf '%s\0' "$path"
        fi
      done >"$filelist"
    rsync -a --files-from="$filelist" --from0 "$REPO_ROOT/" "$worktree/"
    (
      cd "$REPO_ROOT"
      xargs -0 -r sha1sum <"$filelist"
    ) | LC_ALL=C sort | sha1sum | cut -d ' ' -f1

[script]
_publish:
    STATE_DIR="$XDG_CACHE_HOME/homelab-dev"

    revision="$(just dev _snapshot | tail -n1)"
    echo "Publishing dev snapshot to local OCI registry..."
    flux push artifact "oci://localhost:5001/homelab:dev" \
      --path="$STATE_DIR/worktree" \
      --source="local://homelab" \
      --revision="dev@sha1:${revision}" \
      --insecure-registry >/dev/null
    echo "Published localhost:5001/homelab:dev (${revision})"

# Create Kind, local registry, fake NFS/SMB, and install Flux
[script]
up:
    CLUSTER_NAME="homelab-dev"
    KUBE_CONTEXT="kind-homelab-dev"

    if kind get clusters | grep -qx "$CLUSTER_NAME"; then
      echo "Kind cluster $CLUSTER_NAME already exists; use 'just dev sync' or 'just dev down'." >&2
      exit 1
    fi

    kind create cluster --name "$CLUSTER_NAME" --config kind.dev.yaml --wait 120s

    echo "Disabling Kind default StorageClass..."
    kubectl --context "$KUBE_CONTEXT" patch storageclass standard \
      --type=merge \
      --patch '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false","storageclass.beta.kubernetes.io/is-default-class":"false"}}}' >/dev/null
    if kubectl --context "$KUBE_CONTEXT" get storageclass standard -o yaml | grep -q 'is-default-class: "\?true'; then
      echo "Kind standard StorageClass is still default" >&2
      exit 1
    fi

    docker compose -p homelab-dev -f compose.dev.yaml up -d
    just dev _publish

    echo "Installing Flux controllers..."
    flux install --context "$KUBE_CONTEXT"
    flux --context "$KUBE_CONTEXT" create source oci flux-system \
      --namespace flux-system \
      --url oci://dev-registry:5000/homelab \
      --tag dev \
      --interval 10s \
      --insecure
    flux --context "$KUBE_CONTEXT" create kustomization flux-system \
      --namespace flux-system \
      --source OCIRepository/flux-system \
      --path ./kubernetes/clusters/dev \
      --prune \
      --interval 10s \
      --retry-interval 10s \
      --health-check-timeout 10m

    echo
    echo "Dev cluster started from a local working-tree OCI artifact."
    echo "Update:  just dev sync"
    echo "Remove:  just dev down"

# Publish the current working tree and reconcile Flux
[script]
sync:
    CLUSTER_NAME="homelab-dev"
    KUBE_CONTEXT="kind-homelab-dev"

    kind get clusters | grep -qx "$CLUSTER_NAME" || {
      echo "Kind cluster $CLUSTER_NAME does not exist; run 'just dev up'." >&2
      exit 1
    }
    just dev _publish
    flux --context "$KUBE_CONTEXT" reconcile source oci flux-system -n flux-system
    flux --context "$KUBE_CONTEXT" reconcile kustomization flux-system -n flux-system --with-source

# Destroy the dev cluster and local dev state
[script]
down:
    CLUSTER_NAME="homelab-dev"
    STATE_DIR="$XDG_CACHE_HOME/homelab-dev"

    # Delete Kind before Compose so kubelet/CSI can unmount NFS/SMB while the
    # backing services still exist.
    if kind get clusters | grep -qx "$CLUSTER_NAME"; then
      kind delete cluster --name "$CLUSTER_NAME"
    fi
    docker compose -p homelab-dev -f compose.dev.yaml down -v --remove-orphans || true
    rm -rf "$STATE_DIR"
    echo "Removed dev cluster, local OCI registry, snapshot, and fake storage data."

# Show Flux sources, Kustomizations, and HelmReleases
[script]
status:
    KUBE_CONTEXT="kind-homelab-dev"

    echo "== sources =="
    flux --context "$KUBE_CONTEXT" get sources oci -A || true
    echo
    echo "== kustomizations =="
    flux --context "$KUBE_CONTEXT" get kustomizations -A || true
    echo
    echo "== helm releases =="
    flux --context "$KUBE_CONTEXT" get helmreleases -A || true
