#!/bin/bash
# Idempotent head-node setup. Safe to re-run at any time: it is how you recover
# a head that came up wrong, and it is what cloud-init runs on first boot.
#
# Everything here is local system state. Anything that needs the OpenStack API
# goes through the `cluster` tool, which is the single place that knows how to
# talk to the cloud.
set -euo pipefail

ENV_FILE=/etc/cluster/cluster.env
HEAD_KEY=/etc/cluster/id_ed25519

# shellcheck source=/dev/null
. "$ENV_FILE"

export DEBIAN_FRONTEND=noninteractive
APT='apt-get -o DPkg::Lock::Timeout=300 -y'

# --- packages. Core is fatal; apptainer and nextflow are best-effort so that a
#     lagging PPA cannot block the cluster from coming up at all. ---
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; chmod +x /usr/sbin/policy-rc.d
$APT update
$APT install software-properties-common
add-apt-repository -y universe
$APT update
$APT install munge slurmctld slurm-client nfs-kernel-server xfsprogs chrony \
  tmux curl jq openjdk-21-jre-headless python3-openstackclient python3-openstacksdk
( add-apt-repository -y ppa:apptainer/ppa && $APT update && $APT install apptainer ) \
  || echo "WARNING: apptainer install failed; see deploy/README.md" >&2
rm -f /usr/sbin/policy-rc.d

# --- OpenStack credential. This is the one secret that has to be supplied by
#     hand, because nothing on the head can mint it: an application credential
#     cannot create another application credential. ---
for _v in OS_AUTH_URL OS_APP_CRED_ID OS_APP_CRED_SECRET; do
  case "${!_v:-}" in
    ""|*CHANGEME*)
      echo "ERROR: $_v is unset or still a CHANGEME placeholder in $ENV_FILE." >&2
      echo "       You probably pasted head.yaml.example rather than your own" >&2
      echo "       filled-in head.yaml. Copy it first:" >&2
      echo "         cp head.yaml.example head.yaml   # git-ignored" >&2
      echo "       Then set OS_AUTH_URL to your Keystone endpoint, and create an" >&2
      echo "       application credential with the 'member' role in Horizon under" >&2
      echo "       Identity -> Application Credentials." >&2
      exit 1
      ;;
  esac
done
unset _v

write_clouds() {  # <path> <owner>
  # Create ~/.config explicitly.
  local dir parent
  dir=$(dirname "$1")
  parent=$(dirname "$dir")
  install -d -m 0755 -o "$2" -g "$2" "$parent"
  install -d -m 0700 -o "$2" -g "$2" "$dir"
  cat > "$1" <<CLOUDS
clouds:
  openstack:
    auth_type: v3applicationcredential
    auth:
      auth_url: ${OS_AUTH_URL}
      application_credential_id: ${OS_APP_CRED_ID}
      application_credential_secret: ${OS_APP_CRED_SECRET}
    region_name: "${OS_REGION_NAME:-RegionOne}"
    # The management endpoints on the internal network are not routed to tenant
    # subnets. Only the public ones are reachable from here.
    interface: "public"
    identity_api_version: 3
CLOUDS
  chown "$2:$2" "$1"
  chmod 0600 "$1"
}
write_clouds /root/.config/openstack/clouds.yaml root
write_clouds /home/ubuntu/.config/openstack/clouds.yaml ubuntu

# --- munge key. Generated here, once, and handed to each compute node in its
#     user-data by `cluster up`. ---
install -d -o munge -g munge -m 0700 /etc/munge
if [ ! -f /etc/munge/munge.key ]; then
  dd if=/dev/urandom bs=1 count=1024 of=/etc/munge/munge.key status=none
  chown munge:munge /etc/munge/munge.key
  chmod 0400 /etc/munge/munge.key
fi
systemctl enable --now chrony
systemctl enable munge
systemctl restart munge

# --- the head's own SSH key. Compute nodes get this public key injected at
#     create time, which is what lets the head configure them afterwards. A node
#     launched without any key is unreachable forever, console included. ---
install -d -m 0700 /etc/cluster
if [ ! -f "$HEAD_KEY" ]; then
  ssh-keygen -t ed25519 -N '' -C "cluster-head" -f "$HEAD_KEY" >/dev/null
fi
chmod 0600 "$HEAD_KEY"

install -d -o slurm -g slurm /var/spool/slurmctld /var/spool/slurmd /var/log/slurm

# --- sanity-check API access now, so a bad credential fails here with a clear
#     message rather than later inside `cluster up`. ---
eval "$(cluster facts)"
echo "head=${CLUSTER_HEAD_NAME} ip=${CLUSTER_HEAD_IP} net=${CLUSTER_NETWORK} cidrs=${CLUSTER_CIDRS}"

# The mountpoint always exists so paths resolve; `cluster volume attach` fills it.
install -d -m 0755 /data

# --- Point Nextflow and Apptainer at /data ---
cat > /etc/profile.d/cluster-tmp.sh <<'PROFILE'
export TMPDIR=/data/tmp
export APPTAINER_TMPDIR=/data/tmp
export APPTAINER_CACHEDIR=/data/apptainer-cache
export NXF_HOME=/data/.nextflow
export NXF_OPTS="-Djava.io.tmpdir=/data/tmp"
PROFILE
chmod 0644 /etc/profile.d/cluster-tmp.sh

# --- Nextflow (needs Java; the pipeline manifest requires >=26.04.0) ---
if [ ! -x /usr/local/bin/nextflow ]; then
  ( curl -s https://get.nextflow.io | bash \
    && install -m 0755 nextflow /usr/local/bin/nextflow && rm -f nextflow ) \
    || echo "WARNING: nextflow install failed; install it manually" >&2
fi

cat <<'NEXT'

head-setup done. The head is ready; nothing else has been created yet.
Build the cluster from here, checking each step as you go:

  cluster flavors                        # memory each flavor leaves for jobs
  cluster volume list                    # existing volumes
  sudo cluster volume create --size 100  # or reuse one you already have
  sudo cluster volume attach cp-data     # sets up and exports /data
  sudo cluster up --nodes 8 --flavor m1.large
  sudo cluster status

See deploy/README.md for the full command reference. `cluster --help` works too.

NEXT
