#!/usr/bin/env python3
"""Build and manage the Cell Painting SLURM cluster from the head node.

The head node is the only thing created by hand. Everything else is created
here through the OpenStack API. The head discovers its own image, network,
subnet and security groups and reuses them for every compute node, so nothing
about the cluster's shape has to be configured twice.

  cluster flavors   list flavors and the memory each leaves for jobs
  cluster volume    list/create/attach the shared /data volume
  cluster up        create or scale compute nodes, then wire up SLURM
  cluster status    instances plus sinfo
  cluster down      delete this cluster's compute nodes
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import textwrap
import time
import urllib.request
from pathlib import Path

import openstack

ENV_FILE = Path("/etc/cluster/cluster.env")
HEAD_KEY = Path("/etc/cluster/id_ed25519")
MUNGE_KEY = Path("/etc/munge/munge.key")
SLURM_CONF = Path("/etc/slurm/slurm.conf")
CGROUP_CONF = Path("/etc/slurm/cgroup.conf")
METADATA = "http://169.254.169.254/openstack/latest/meta_data.json"

HOSTS_BEGIN = "# BEGIN cluster-managed"
HOSTS_END = "# END cluster-managed"

# RealMemory must not exceed what the node reports or slurmctld rejects it with
# "Low RealMemory ... INVAL". We measure a real booted node rather than trusting
# the flavor's nominal RAM (a 4096 MB flavor reports ~3916), then hold back a
# little so a node with a slightly different kernel still fits.
MEM_MARGIN_FRAC = 0.01
MEM_MARGIN_MIN_MB = 64

# MemSpecLimit is subtracted from RealMemory when scheduling, reserving memory
# the kernel, sshd, slurmd and the NFS client can always have. This is not
# optional slack. Jobs here have been observed using 100% of their allocation,
# so without a reservation Slurm would pack a node to its last megabyte of
# really-used memory and the next kernel allocation would kill something that
# matters. Override per-cluster with --mem-spec-limit if 10% is wrong for you.
MEM_RESERVE_FRAC = 0.10
MEM_RESERVE_MIN_MB = 2048

# A flavor's nominal RAM is not what the node reports. Measured ratios were
# 3916/4096 = 0.956 and 50189/51200 = 0.980, so the loss is mostly fixed
# overhead rather than a clean fraction. 0.95 under-states both, which is the
# safe direction to be wrong in. Only used when there is no booted node to
# measure, i.e. by `cluster flavors`.
FLAVOR_MEM_EST_FRAC = 0.95

# nfsd's stock 8 threads is the usual reason /data feels slow with the whole
# cluster on it. Every node's reads and writes queue behind those 8. The right
# number tracks how many requests the clients have in flight, NOT the head's
# core count.
NFSD_THREADS = 128


def memory_plan(node_mb, reserve_override=None):
    """Turn a node's total memory into (RealMemory, MemSpecLimit, schedulable).

    Single source of truth so `cluster flavors` estimates exactly what
    `cluster up` will configure, rather than approximating it separately.
    """
    real = node_mb - max(MEM_MARGIN_MIN_MB, int(node_mb * MEM_MARGIN_FRAC))
    reserve = (
        int(reserve_override)
        if reserve_override
        else max(MEM_RESERVE_MIN_MB, int(real * MEM_RESERVE_FRAC))
    )
    return real, reserve, max(0, real - reserve)


SSH_OPTS = [
    "-o",
    "StrictHostKeyChecking=no",
    "-o",
    "UserKnownHostsFile=/dev/null",
    "-o",
    "LogLevel=ERROR",
    "-o",
    "ConnectTimeout=10",
    "-o",
    "BatchMode=yes",
]


def die(msg):
    print(f"cluster: error: {msg}", file=sys.stderr)
    sys.exit(1)


def info(msg):
    print(f"==> {msg}", flush=True)


def warn(msg):
    print(f"cluster: warning: {msg}", file=sys.stderr, flush=True)


def load_env():
    """Read the key=value file cloud-init wrote from the launch template."""
    try:
        text = ENV_FILE.read_text()
    except FileNotFoundError:
        die(f"{ENV_FILE} not found. This must run on a head node built from head.yaml.")
    except PermissionError:
        # Path.exists() reports False when it cannot traverse the directory, so
        # testing that first would blame a missing file for a permission problem.
        die(f"{ENV_FILE} is not readable by this user. Re-run with sudo.")
    env = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def connect():
    try:
        return openstack.connect(cloud="openstack")
    except Exception as e:  # noqa: BLE001 - surface any auth/config problem plainly
        die(f"could not connect to OpenStack: {e}")


def attr(obj, name, default=None):
    """Read a field from an SDK object or a plain dict.

    The SDK returns nested things like server.image and server.flavor as objects
    in some versions and dicts in others, and the head runs whatever Ubuntu
    packages that day.
    """
    if obj is None:
        return default
    if isinstance(obj, dict):
        return obj.get(name, default)
    return getattr(obj, name, default)


def self_id():
    """Our own instance UUID, straight from the metadata service."""
    try:
        with urllib.request.urlopen(METADATA, timeout=10) as r:
            return json.load(r)["uuid"]
    except Exception as e:  # noqa: BLE001
        die(f"could not read instance metadata: {e}")


def discover(conn):
    """Everything about the cluster's shape, learned from the head itself.

    Compute nodes are built to match the head, so image/network/security groups
    are never configured by hand and cannot drift apart.
    """
    server = conn.compute.get_server(self_id())
    if server is None:
        die("could not find this instance via the API. Check the credential's project.")

    net_name = next(iter(server.addresses), None)
    if not net_name:
        die("this instance has no network attached")

    fixed_ip = None
    for addr in server.addresses[net_name]:
        if addr.get("OS-EXT-IPS:type") == "fixed":
            fixed_ip = addr["addr"]
            break
    if not fixed_ip:
        die(f"no fixed IP found on network {net_name}")

    network = conn.network.find_network(net_name, ignore_missing=False)
    subnets = list(conn.network.subnets(network_id=network.id))
    if not subnets:
        die(f"network {net_name} has no subnet")
    cidrs = [s.cidr for s in subnets]

    groups = [n for n in (attr(g, "name") for g in (server.security_groups or [])) if n]
    if not groups:
        die("this instance has no security group; compute nodes could not reach it")

    image_id = attr(server.image, "id")
    if not image_id:
        die("could not determine this instance's image")

    return {
        "id": server.id,
        "name": server.name,
        "ip": fixed_ip,
        "network": net_name,
        "network_id": network.id,
        "cidrs": cidrs,
        "security_groups": groups,
        "image_id": image_id,
    }


def head_pubkey():
    pub = HEAD_KEY.with_suffix(".pub")
    if not pub.exists():
        die(f"{pub} missing. Run head-setup.sh first.")
    return pub.read_text().strip()


AUTH_KEY_RE = re.compile(
    r"(?:^|\s)"
    r"(ssh-(?:rsa|dss|ed25519)"
    r"|ecdsa-sha2-nistp(?:256|384|521)"
    r"|sk-ssh-ed25519@openssh\.com"
    r"|sk-ecdsa-sha2-nistp256@openssh\.com)"
    r"\s+(AAAA[A-Za-z0-9+/]+={0,3})"
)


def bare_pubkey(line):
    """
    Reduce an authorized_keys line to "<type> <base64>", or None if it holds no key.
    """
    m = AUTH_KEY_RE.search(line)
    return f"{m.group(1)} {m.group(2)}" if m else None


def operator_pubkeys():
    """Whatever keys can already reach the head, so they also reach compute nodes."""
    keys = []
    for path in (
        Path("/home/ubuntu/.ssh/authorized_keys"),
        Path("/root/.ssh/authorized_keys"),
    ):
        if path.exists():
            for line in path.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                key = bare_pubkey(line)
                if key:
                    keys.append(key)
    return keys


def api_retry(fn, *a, tries=5, delay=10, **kw):
    """Call an API function, retrying transient server-side failures.

    This cloud's Nova has been seen returning 500 mid-poll with
    oslo_db.exception.DBConnectionError, which is the control plane having a bad
    moment, not anything wrong with the request. Building a cluster makes API
    calls for ~15 minutes, so meeting one is likely, and a traceback there
    strands the instances it already created.
    """
    last = None
    for attempt in range(tries):
        try:
            return fn(*a, **kw)
        except Exception as e:  # noqa: BLE001 - re-raised below unless transient
            last = e
            if isinstance(e, openstack.exceptions.HttpException):
                # 5xx is the control plane failing. 4xx is us: a bad request, a
                # missing resource, a credential without the role. Retrying that
                # just delays the real error by 40 seconds.
                transient = e.status_code is None or e.status_code >= 500
            elif isinstance(e, openstack.exceptions.SDKException):
                transient = True  # connection/timeout failures below HTTP
            else:
                raise  # not an API problem at all, do not mask it
            if not transient:
                raise
            if attempt < tries - 1:
                print(
                    f"warning: API call failed ({type(e).__name__}), "
                    f"retrying in {delay}s",
                    file=sys.stderr,
                )
                time.sleep(delay)
    raise last


def wait_gone(conn, srv, timeout=300):
    """Poll until a deleted server actually disappears, so its name and index
    are free before we recreate it."""
    end = time.time() + timeout
    while time.time() < end:
        if api_retry(conn.compute.find_server, srv.id, ignore_missing=True) is None:
            return
        time.sleep(5)
    die(f"{srv.name} did not finish deleting within {timeout}s")


def wait_active(conn, srv, timeout=900):
    """Poll a server to ACTIVE, tolerating transient API failures."""
    end = time.time() + timeout
    while time.time() < end:
        s = api_retry(conn.compute.get_server, srv.id)
        if s.status == "ACTIVE":
            return s
        if s.status == "ERROR":
            die(f"{srv.name} went to ERROR. Check it in Horizon, then re-run.")
        time.sleep(5)
    die(f"{srv.name} was still {s.status} after {timeout}s. Re-run `cluster up`.")


def ssh(ip, cmd, timeout=30):
    return subprocess.run(
        ["ssh", "-i", str(HEAD_KEY), *SSH_OPTS, f"ubuntu@{ip}", cmd],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def wait_for_ssh(ip, deadline):
    while time.time() < deadline:
        r = ssh(ip, "true", timeout=15)
        if r.returncode == 0:
            return True
        time.sleep(5)
    return False


def measure_memory(ip):
    """Ask a real node how much memory it actually has."""
    r = ssh(ip, "awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo")
    if r.returncode != 0 or not r.stdout.strip().isdigit():
        return None
    return int(r.stdout.strip())


def compute_user_data(facts, name):
    """cloud-config for one compute node."""
    munge_b64 = base64.b64encode(MUNGE_KEY.read_bytes()).decode()
    keys = [head_pubkey(), *operator_pubkeys()]
    keys_yaml = "\n".join(f"  - {k}" for k in dict.fromkeys(keys))
    head_ip = facts["ip"]
    head_name = facts["name"]

    return f"""#cloud-config
hostname: {name}
preserve_hostname: false

ssh_authorized_keys:
{keys_yaml}

write_files:
  - path: /etc/munge/munge.key.b64
    permissions: '0400'
    content: {munge_b64}

  - path: /usr/local/sbin/compute-setup.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Idempotent compute-node setup. Safe to re-run.
      set -euxo pipefail
      export DEBIAN_FRONTEND=noninteractive
      APT='apt-get -o DPkg::Lock::Timeout=300 -y'

      # Keep package postinst from starting daemons before their config exists.
      printf '#!/bin/sh\\nexit 101\\n' > /usr/sbin/policy-rc.d; chmod +x /usr/sbin/policy-rc.d
      $APT update
      $APT install software-properties-common
      add-apt-repository -y universe
      $APT update
      $APT install munge slurmd slurm-client nfs-common chrony
      ( add-apt-repository -y ppa:apptainer/ppa && $APT update && $APT install apptainer ) \\
        || echo "WARNING: apptainer install failed; see deploy/README.md" >&2
      rm -f /usr/sbin/policy-rc.d

      install -d -o munge -g munge -m 0700 /etc/munge
      base64 -d /etc/munge/munge.key.b64 > /etc/munge/munge.key
      chown munge:munge /etc/munge/munge.key
      chmod 0400 /etc/munge/munge.key

      grep -q ' {head_name}$' /etc/hosts || echo "{head_ip} {head_name}" >> /etc/hosts

      install -d -o slurm -g slurm /var/spool/slurmd /var/log/slurm

      # Configless: slurmd pulls slurm.conf and cgroup.conf from the controller,
      # so this node never holds a copy that can drift out of sync.
      echo 'SLURMD_OPTIONS="--conf-server {head_ip}"' > /etc/default/slurmd

      # The controller may still be writing slurm.conf when this node boots.
      # Retry forever instead of failing the unit and needing a manual restart.
      install -d /etc/systemd/system/slurmd.service.d
      printf '[Service]\\nRestart=always\\nRestartSec=15\\n' \\
        > /etc/systemd/system/slurmd.service.d/retry.conf

      install -d -m 0755 /data
      grep -q ' /data ' /etc/fstab || \\
        echo "{head_ip}:/data /data nfs rw,_netdev,hard,nofail,x-systemd.automount,x-systemd.mount-timeout=30 0 0" >> /etc/fstab
      systemctl daemon-reload
      systemctl start data.automount 2>/dev/null || mount -a || \\
        echo "WARNING: /data not mounted yet; it will mount on first access" >&2

      systemctl enable --now chrony
      systemctl enable munge slurmd
      systemctl restart munge
      systemctl restart slurmd
      echo "compute-setup done: $(hostname)"

runcmd:
  - bash /usr/local/sbin/compute-setup.sh
"""


def existing_nodes(conn, cluster_name):
    """Compute nodes this tool created, identified by metadata we set ourselves.

    Nothing else is ever touched: `down` can only delete what `up` tagged.
    """
    out = []
    for s in api_retry(lambda: list(conn.compute.servers(details=True))):
        meta = s.metadata or {}
        if meta.get("cluster") == cluster_name and meta.get("role") == "compute":
            out.append(s)
    return sorted(out, key=lambda s: node_index(s.name))


def node_index(name):
    m = re.search(r"-(\d+)$", name)
    return int(m.group(1)) if m else 0


def server_ip(server, net_name):
    for addr in (server.addresses or {}).get(net_name, []):
        if addr.get("OS-EXT-IPS:type") == "fixed":
            return addr["addr"]
    return None


def write_hosts_block(entries):
    """Replace the managed block in /etc/hosts, leaving everything else alone."""
    block = [HOSTS_BEGIN, *[f"{ip}\t{name}" for name, ip in entries], HOSTS_END]
    text = Path("/etc/hosts").read_text()
    if HOSTS_BEGIN in text:
        text = re.sub(
            rf"{re.escape(HOSTS_BEGIN)}.*?{re.escape(HOSTS_END)}",
            "\n".join(block),
            text,
            flags=re.S,
        )
    else:
        text = text.rstrip("\n") + "\n" + "\n".join(block) + "\n"
    Path("/etc/hosts").write_text(text)


def write_slurm_conf(facts, node_spec, cpus, real_memory, mem_spec_limit):
    SLURM_CONF.parent.mkdir(parents=True, exist_ok=True)
    SLURM_CONF.write_text(
        textwrap.dedent(f"""\
        ClusterName=cellpainting
        SlurmctldHost={facts["name"]}
        # enable_configless lets slurmd fetch this file from the controller, so
        # this is the only copy in the cluster and changes need no fan-out.
        SlurmctldParameters=enable_configless
        AuthType=auth/munge
        SlurmUser=slurm
        SlurmctldPort=6817
        SlurmdPort=6818
        ReturnToService=2
        StateSaveLocation=/var/spool/slurmctld
        SlurmdSpoolDir=/var/spool/slurmd
        SlurmctldPidFile=/run/slurmctld.pid
        SlurmdPidFile=/run/slurmd.pid
        SchedulerType=sched/backfill
        SelectType=select/cons_tres
        SelectTypeParameters=CR_CPU_Memory
        ProctrackType=proctrack/cgroup
        TaskPlugin=task/cgroup
        SlurmctldTimeout=120
        SlurmdTimeout=300
        SlurmctldLogFile=/var/log/slurm/slurmctld.log
        SlurmdLogFile=/var/log/slurm/slurmd.log
        NodeName={node_spec} CPUs={cpus} RealMemory={real_memory} MemSpecLimit={mem_spec_limit} State=UNKNOWN
        PartitionName=compute Nodes=ALL Default=YES MaxTime=INFINITE State=UP
        """)
    )
    CGROUP_CONF.write_text(
        textwrap.dedent("""\
        CgroupPlugin=cgroup/v2
        ConstrainCores=yes
        ConstrainRAMSpace=yes
        """)
    )


def cmd_up(args):
    env = load_env()
    conn = connect()
    facts = discover(conn)
    cluster_name = env.get("CLUSTER_NAME", "cp")

    flavor_name = args.flavor
    want = args.nodes
    if want < 1:
        die("--nodes must be at least 1")

    flavor = conn.compute.find_flavor(flavor_name, ignore_missing=True)
    if flavor is None:
        names = ", ".join(sorted(f.name for f in conn.compute.flavors()))
        die(
            f"unknown flavor {flavor_name!r}. Available: {names}\n"
            f"       Run `cluster flavors` to see them with their usable memory."
        )

    info(
        f"cluster {cluster_name}: {want} x {flavor.name} "
        f"({flavor.vcpus} vCPU, {flavor.ram} MB) on {facts['network']}"
    )

    have = existing_nodes(conn, cluster_name)

    # An instance in ERROR never booted: it holds nothing, has no fixed IP, and
    # will never get one. Replace it rather than let it block the build forever.
    broken = [s for s in have if s.status == "ERROR"]
    for s in broken:
        full = api_retry(conn.compute.get_server, s.id)
        reason = attr(full.fault, "message") or "no reason reported"
        info(f"{s.name} is in ERROR ({reason}); deleting it to rebuild")
        api_retry(conn.compute.delete_server, s.id)
    for s in broken:
        wait_gone(conn, s)
    have = [s for s in have if s.status != "ERROR"]

    # Fill gaps by index rather than counting. If compute-2 was deleted by hand,
    # counting would try to create compute-3 and collide with the live one.
    taken = {node_index(s.name) for s in have}
    todo = [i for i in range(1, want + 1) if i not in taken]
    if not todo:
        info(f"{len(have)} compute nodes already exist, creating none")
    created = []
    for i in todo:
        name = f"{cluster_name}-compute-{i}"
        info(f"creating {name}")
        srv = conn.compute.create_server(
            name=name,
            image_id=facts["image_id"],
            flavor_id=flavor.id,
            networks=[{"uuid": facts["network_id"]}],
            security_groups=[{"name": g} for g in facts["security_groups"]],
            user_data=base64.b64encode(
                compute_user_data(facts, name).encode()
            ).decode(),
            metadata={"cluster": cluster_name, "role": "compute"},
        )
        created.append(srv)

    if created:
        info(f"waiting for {len(created)} instances to become ACTIVE")
        for srv in created:
            wait_active(conn, srv)

    nodes = existing_nodes(conn, cluster_name)
    entries = []
    for s in nodes:
        ip = server_ip(api_retry(conn.compute.get_server, s.id), facts["network"])
        if not ip:
            die(f"{s.name} has no fixed IP")
        entries.append((s.name, ip))

    info("writing /etc/hosts")
    write_hosts_block([(facts["name"], facts["ip"]), *entries])

    # Export to the new nodes before waiting on SSH
    if data_device():
        write_exports([ip for _, ip in entries])
    else:
        warn(
            "no volume is mounted at /data, so the new nodes have nothing to "
            "mount. Attach one with `sudo cluster volume attach NAME`, which "
            "also exports it to them."
        )

    # cloud-init on a fresh node takes a few minutes (apt + apptainer PPA).
    info("waiting for SSH on compute nodes (cloud-init installs packages first)")
    deadline = time.time() + 900
    ready = [(n, ip) for n, ip in entries if wait_for_ssh(ip, deadline)]
    if not ready:
        die(
            "no compute node became reachable over SSH; check cloud-init on one of them"
        )
    if len(ready) < len(entries):
        missing = [n for n, _ in entries if n not in {r[0] for r in ready}]
        print(f"warning: not reachable yet: {', '.join(missing)}", file=sys.stderr)

    measured = measure_memory(ready[0][1])
    if not measured:
        # We already SSH'd to this node to get here, so a failure now is
        # something unexpected. Guessing would risk configuring RealMemory above
        # what the node reports, which drains every node with "Low RealMemory".
        die(
            f"could not read memory from {ready[0][0]}. The nodes exist and are "
            f"fine; fix SSH to them and re-run `cluster up`, which will skip "
            f"creation and pick up here."
        )
    info(f"measured {measured} MB on {ready[0][0]} (flavor claims {flavor.ram})")

    override = args.mem_spec_limit or env.get("MEM_SPEC_LIMIT")
    real_memory, mem_spec_limit, schedulable = memory_plan(measured, override)
    if schedulable <= 0:
        die(
            f"MemSpecLimit {mem_spec_limit} leaves nothing schedulable out of "
            f"RealMemory {real_memory}. Lower it with --mem-spec-limit."
        )
    info(
        f"RealMemory={real_memory}, MemSpecLimit={mem_spec_limit} reserved for the "
        f"system, {schedulable} MB per node for jobs"
    )

    # Derive the NodeName spec from the indices that actually exist, so a gap
    # (a node deleted by hand) never makes slurm.conf claim a node that is gone.
    idx = sorted(node_index(s.name) for s in nodes)
    if idx == list(range(1, len(idx) + 1)):
        node_spec = (
            f"{cluster_name}-compute-[1-{len(idx)}]"
            if len(idx) > 1
            else f"{cluster_name}-compute-1"
        )
    else:
        node_spec = f"{cluster_name}-compute-[{','.join(str(i) for i in idx)}]"
    info(f"writing slurm.conf ({node_spec})")
    write_slurm_conf(facts, node_spec, flavor.vcpus, real_memory, mem_spec_limit)

    info("restarting slurmctld")
    # restart, not reconfigure: node addresses are only resolved at daemon start.
    subprocess.run(["systemctl", "restart", "slurmctld"], check=True)
    time.sleep(3)

    info("pushing /etc/hosts and restarting slurmd on compute nodes")
    hosts_block = Path("/etc/hosts").read_text()
    for name, ip in ready:
        payload = base64.b64encode(hosts_block.encode()).decode()
        ssh(
            ip,
            f"echo {payload} | base64 -d | sudo tee /etc/hosts >/dev/null && "
            f"sudo systemctl restart slurmd",
            timeout=60,
        )

    info("done. Current state:")
    show_sinfo()


def cmd_down(args):
    env = load_env()
    conn = connect()
    cluster_name = env.get("CLUSTER_NAME", "cp")
    nodes = existing_nodes(conn, cluster_name)
    me = self_id()

    nodes = [n for n in nodes if n.id != me]
    if not nodes:
        info(f"no compute nodes tagged cluster={cluster_name}")
        return

    print(f"About to DELETE {len(nodes)} instances tagged cluster={cluster_name}:")
    for n in nodes:
        print(f"  {n.name}")
    print("The head node is not affected.")
    if not args.yes:
        typed = input(f"Type the cluster name ({cluster_name}) to confirm: ").strip()
        if typed != cluster_name:
            die("confirmation did not match, nothing deleted")

    for n in nodes:
        info(f"deleting {n.name}")
        conn.compute.delete_server(n.id)
    info("delete requested for all compute nodes")

    # Drop them from the export now rather than after waiting for the deletes to
    # finish. These addresses go back to the pool and can be handed to another
    # project's instance, which would otherwise inherit rw access to /data. The
    # nodes losing the export early costs nothing: they are being destroyed.
    if data_device():
        write_exports([])


def show_sinfo():
    """Print sinfo.

    Without slurm.conf, sinfo falls back to configless discovery and emits four
    lines about a DNS SRV lookup, which reads like a fault but only means the
    cluster has not been built yet.
    """
    if not SLURM_CONF.exists():
        print("SLURM is not configured yet: no compute nodes have been wired up.")
        print("Run `sudo cluster up --nodes N --flavor FLAVOR`.")
        return
    subprocess.run(["sinfo"], check=False)


def cmd_flavors(args):
    """List flavors and the memory each would actually leave for jobs."""
    conn = connect()
    rows = []
    for f in conn.compute.flavors():
        _, _, sched = memory_plan(int(f.ram * FLAVOR_MEM_EST_FRAC))
        rows.append((f.name, f.vcpus, f.ram, f.disk, sched))
    if not rows:
        die("no flavors visible to this credential")
    rows.sort(key=lambda r: (r[2], r[1]))

    print(f"{'NAME':<18}{'VCPUS':>6}{'RAM MB':>9}{'DISK':>6}{'EST JOB MEM':>13}")
    for name, vcpus, ram, disk, sched in rows:
        print(f"{name:<18}{vcpus:>6}{ram:>9}{disk:>6}{sched:>13}")

    print()
    print("EST JOB MEM is what a node leaves for jobs, after the kernel's cut and")
    print(
        "MemSpecLimit. Estimated conservatively; `cluster up` measures a booted node."
    )
    print("A node must fit the largest single task, or that task pends forever however")
    print("many nodes you add.")


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def block_devices():
    """Whole block devices, by full path. Used to spot the one that appears
    after an attach, rather than assuming /dev/vdb: the guest names devices in
    attach order, so a second volume lands on vdc and a hardcoded path misses."""
    return set(run(["lsblk", "-dnpo", "NAME"]).stdout.split())


def blkid(dev, field):
    return run(["blkid", "-o", "value", "-s", field, dev]).stdout.strip()


def compute_node_ips(conn, facts, cluster_name):
    """Fixed IPs of this cluster's compute nodes, for the /data export."""
    out = []
    for s in existing_nodes(conn, cluster_name):
        ip = server_ip(s, facts["network"])
        if ip:
            out.append(ip)
    return out


def write_exports(node_ips):
    Path("/etc/exports").write_text(
        "".join(f"/data {ip}(rw,async,no_subtree_check)\n" for ip in node_ips)
    )
    # Written here rather than in head-setup.sh so that re-running an attach,
    # which is the documented fix for a bad export, also re-applies this.
    Path("/etc/nfs.conf.d").mkdir(parents=True, exist_ok=True)
    Path("/etc/nfs.conf.d/threads.conf").write_text(
        "# Written by `cluster volume attach`. Do not edit; it is overwritten.\n"
        f"[nfsd]\nthreads={NFSD_THREADS}\n"
    )
    run(["systemctl", "enable", "--now", "nfs-kernel-server"])
    if run(["exportfs", "-ra"]).returncode != 0:
        die("exportfs -ra failed")
    check_nfsd_threads()
    if node_ips:
        info(f"exporting /data to {len(node_ips)} compute nodes")
    else:
        # Silence here would look like success and then fail later as an
        # unexplained empty /data, so say it plainly.
        info("/data is exported to nothing: this cluster has no compute nodes yet")


def check_nfsd_threads():
    """Warn if nfsd is not actually running NFSD_THREADS threads.

    rpc.nfsd reads its config only at startup and `enable --now` will not
    restart an nfsd that is already up, so attaching onto a running server can
    leave the old count in place. Ask the kernel rather than trust the file we
    just wrote, so a config written but never read surfaces here rather than as
    an unexplained slow /data.
    """
    threads = Path("/proc/fs/nfsd/threads")
    if not threads.exists():  # nfsd not up; nothing to compare against.
        return
    actual = threads.read_text().strip()
    if actual != str(NFSD_THREADS):
        warn(
            f"nfsd is running {actual} threads, not the configured "
            f"{NFSD_THREADS}. /data will serve the cluster more slowly than it "
            f"should. Apply with: sudo systemctl restart nfs-kernel-server"
        )


def data_device():
    """The device currently backing /data, or None if nothing is mounted there."""
    r = run(["findmnt", "-n", "-o", "SOURCE", "--mountpoint", "/data"])
    return r.stdout.strip() if r.returncode == 0 else None


def setup_data(dev, force_format, node_ips):
    """Make `dev` into /data: format if safe, mount, export to `node_ips`."""
    current = data_device()
    if current and current != dev:
        die(
            f"/data is already mounted from {current}, so {dev} cannot become /data.\n"
            f"       This command manages the single shared /data volume.\n"
            f"       To grow storage, extend the existing volume instead:\n"
            f"         openstack volume set --size <bigger> <name> && sudo xfs_growfs /data\n"
            f"       To genuinely replace it, unmount and detach {current} first."
        )
    fs = blkid(dev, "TYPE")
    if fs == "xfs":
        info(f"{dev} already holds xfs, keeping it")
    elif fs == "":
        info(f"{dev} is blank, creating xfs")
        if run(["mkfs.xfs", "-f", dev]).returncode != 0:
            die(f"mkfs.xfs failed on {dev}")
    elif force_format:
        print(
            f"warning: --force-format: DESTROYING the {fs} filesystem on {dev}",
            file=sys.stderr,
        )
        run(["wipefs", "-a", dev])
        if run(["mkfs.xfs", "-f", dev]).returncode != 0:
            die(f"mkfs.xfs failed on {dev}")
    else:
        # Never reformat a volume that holds someone's data. The caller asked
        # for a volume by name, and a name is not a promise that it is empty.
        die(
            f"{dev} already holds a {fs} filesystem, not xfs.\n"
            f"       Refusing to format: that would destroy whatever is on it.\n"
            f"       Mount it by hand to keep it, or pass --force-format to erase it."
        )

    uuid = blkid(dev, "UUID")
    if not uuid:
        die(f"no filesystem UUID on {dev} after formatting")

    Path("/data").mkdir(parents=True, exist_ok=True)
    # Mount by UUID, not by device path: the kernel can name the same volume
    # differently across reboots, and an fstab pointing at the wrong disk is
    # a bad way to find that out.
    fstab = Path("/etc/fstab")
    kept = [ln for ln in fstab.read_text().splitlines() if " /data " not in ln]
    fstab.write_text(
        "\n".join([*kept, f"UUID={uuid} /data xfs defaults,_netdev 0 2", ""])
    )

    if run(["mountpoint", "-q", "/data"]).returncode != 0:
        if run(["mount", "/data"]).returncode != 0:
            die("mount /data failed; check `dmesg` and /etc/fstab")
    info(f"mounted {dev} (UUID={uuid}) at /data")

    run(["chown", "ubuntu:ubuntu", "/data"])
    for d in ("work", "apptainer-cache", "tmp", ".nextflow"):
        (Path("/data") / d).mkdir(exist_ok=True)
        run(["chown", "ubuntu:ubuntu", str(Path("/data") / d)])
    # /etc/profile.d/cluster-tmp.sh is written by head-setup.sh at boot, not
    # here: profile.d is only read by login shells, and this command necessarily
    # runs after you have already logged in.

    write_exports(node_ips)


def cmd_volume_list(args):
    conn = connect()
    vols = list(conn.block_storage.volumes())
    if not vols:
        print("no volumes in this project")
        return
    servers = {s.id: s.name for s in conn.compute.servers()}
    print(f"{'NAME':<26}{'GB':>6}  {'STATUS':<12}ATTACHED TO")
    for v in sorted(vols, key=lambda v: v.name or ""):
        att = v.attachments or []
        where = (
            ", ".join(
                f"{servers.get(a.get('server_id'), (a.get('server_id') or '?')[:8])}"
                f":{a.get('device', '?')}"
                for a in att
            )
            or "-"
        )
        flag = "  <- attachable" if v.status == "available" else ""
        print(f"{(v.name or '(unnamed)'):<26}{v.size:>6}  {v.status:<12}{where}{flag}")
    print()
    print("Attach one as the shared /data with: sudo cluster volume attach NAME")


def running_jobs():
    """How many SLURM jobs are live, or 0 if SLURM is not up yet."""
    if not SLURM_CONF.exists():
        return 0
    r = run(["squeue", "-h", "-o", "%i"])
    if r.returncode != 0:
        return 0
    return len([ln for ln in r.stdout.splitlines() if ln.strip()])


def refresh_data_mounts(conn, facts, cluster_name):
    """Make compute nodes pick up a changed /data."""
    nodes = [s for s in existing_nodes(conn, cluster_name) if s.status == "ACTIVE"]
    if not nodes:
        return
    info(f"refreshing /data on {len(nodes)} compute nodes")
    for s in nodes:
        ip = server_ip(api_retry(conn.compute.get_server, s.id), facts["network"])
        if ip:
            ssh(
                ip,
                "sudo umount -l /data 2>/dev/null; "
                "sudo systemctl restart data.automount 2>/dev/null; true",
                timeout=30,
            )


def cmd_volume_detach(args):
    env = load_env()
    conn = connect()
    facts = discover(conn)
    cluster_name = env.get("CLUSTER_NAME", "cp")

    vol = conn.block_storage.find_volume(args.name, ignore_missing=True)
    if vol is None:
        die(f"no volume named {args.name!r}. `cluster volume list` shows what exists.")
    mine = [a for a in (vol.attachments or []) if a.get("server_id") == facts["id"]]
    if not mine:
        die(
            f"{args.name!r} is not attached to this head, so there is nothing to detach."
        )

    live = running_jobs()
    if live and not args.force:
        die(
            f"{live} SLURM job(s) are still running, and every one of them can be "
            f"using /data.\n"
            f"       Pulling the volume out will fail them. Wait for them to finish, "
            f"or `scancel` them.\n"
            f"       Pass --force to detach anyway."
        )

    current = data_device()
    if not args.yes:
        print(f"About to unexport, unmount and detach {args.name} ({vol.size} GB).")
        print("Every compute node loses /data until you attach another volume.")
        if (
            input(f"Type the volume name ({args.name}) to confirm: ").strip()
            != args.name
        ):
            die("confirmation did not match, nothing done")

    # Unexport first. nfsd holds a reference to the filesystem, so umount would
    # fail with "target is busy" while the export is still live.
    exports = Path("/etc/exports")
    if exports.exists() and exports.read_text().strip():
        info("unexporting /data")
        exports.write_text("")
        run(["exportfs", "-ra"])

    if current:
        info(f"unmounting /data ({current})")
        r = run(["umount", "/data"])
        if r.returncode != 0:
            holders = run(["lsof", "+D", "/data"]).stdout.strip()
            die(
                f"umount /data failed: {r.stderr.strip()}\n"
                f"       Something is still using it. A lazy unmount would hide that "
                f"rather than fix it:\n{holders[:600] or '       (lsof reported nothing)'}"
            )

    # Drop the fstab entry, or the next boot blocks trying to mount a volume
    # that is no longer attached.
    fstab = Path("/etc/fstab")
    kept = [ln for ln in fstab.read_text().splitlines() if " /data " not in ln]
    fstab.write_text("\n".join([*kept, ""]))

    info(f"detaching {args.name}")
    api_retry(conn.compute.delete_volume_attachment, vol.id, facts["id"])
    end = time.time() + 300
    while time.time() < end:
        v = api_retry(conn.block_storage.get_volume, vol.id)
        if v.status == "available":
            break
        time.sleep(5)
    else:
        die(f"{args.name} did not reach 'available' within 300s. Check Horizon.")

    refresh_data_mounts(conn, facts, cluster_name)
    info(f"{args.name} detached. Attach another with: sudo cluster volume attach NAME")


def cmd_volume_create(args):
    env = load_env()
    conn = connect()
    name = args.name or f"{env.get('CLUSTER_NAME', 'cp')}-data"
    if conn.block_storage.find_volume(name, ignore_missing=True):
        die(
            f"a volume named {name!r} already exists. "
            f"Pick another --name, or attach that one."
        )
    info(f"creating {args.size} GB volume {name}")
    vol = conn.block_storage.create_volume(size=args.size, name=name)
    conn.block_storage.wait_for_status(
        vol, status="available", failures=["error"], wait=600
    )
    info(f"created {name}. Attach it with: sudo cluster volume attach {name}")


def cmd_volume_attach(args):
    conn = connect()
    facts = discover(conn)
    cluster_name = load_env().get("CLUSTER_NAME", "cp")
    vol = conn.block_storage.find_volume(args.name, ignore_missing=True)
    if vol is None:
        die(f"no volume named {args.name!r}. `cluster volume list` shows what exists.")

    # Redo the /data setup without touching the attachment. This is
    # what makes the command a repair tool as well as a setup one, e.g. to fix an
    # NFS export after the network changed. Without it, re-running would refuse
    # because the volume is 'in-use', leaving no way to re-export at all.
    mine = [a for a in (vol.attachments or []) if a.get("server_id") == facts["id"]]
    if mine:
        dev = mine[0].get("device")
        if not dev:
            die(f"{args.name!r} is attached here but reports no device. Check `lsblk`.")
        info(f"{args.name} is already attached at {dev}, re-running /data setup")
        setup_data(
            dev, args.force_format, compute_node_ips(conn, facts, cluster_name)
        )
        refresh_data_mounts(conn, facts, cluster_name)
        info("done. /data is mounted and exported.")
        return

    if vol.status != "available":
        die(
            f"volume {args.name!r} is {vol.status} and attached elsewhere. "
            f"Detach it from its current server first."
        )

    # Refuse before attaching rather than after, so a rejected request does not
    # leave a volume dangling off the head with no filesystem set up.
    current = data_device()
    if current:
        die(
            f"/data is already mounted from {current}, so {args.name!r} cannot "
            f"become /data.\n"
            f"       There is only one shared /data. To grow it, extend the volume "
            f"you already have:\n"
            f"         openstack volume set --size <bigger> <name>\n"
            f"         sudo xfs_growfs /data\n"
            f"       To replace it, unmount and detach the current volume first."
        )

    before = block_devices()
    info(f"attaching {args.name} ({vol.size} GB) to {facts['name']}")
    conn.compute.create_volume_attachment(facts["id"], volume_id=vol.id)

    dev = None
    deadline = time.time() + 180
    while time.time() < deadline:
        new = block_devices() - before
        if new:
            dev = sorted(new)[0]
            break
        time.sleep(3)
    if not dev:
        die(
            "volume attached via the API but no new block device appeared. Check `lsblk`."
        )
    info(f"appeared as {dev}")
    setup_data(dev, args.force_format, compute_node_ips(conn, facts, cluster_name))
    refresh_data_mounts(conn, facts, cluster_name)
    info("done. /data is mounted and exported.")


def cmd_facts(args):
    """Emit discovered facts for head-setup.sh to source, so the shell side
    never has to re-derive any of this."""
    conn = connect()
    facts = discover(conn)
    print(f"CLUSTER_SELF_ID={facts['id']}")
    print(f"CLUSTER_HEAD_NAME={facts['name']}")
    print(f"CLUSTER_HEAD_IP={facts['ip']}")
    print(f"CLUSTER_NETWORK='{facts['network']}'")
    print(f"CLUSTER_CIDRS='{' '.join(facts['cidrs'])}'")


def cmd_status(args):
    env = load_env()
    conn = connect()
    facts = discover(conn)
    cluster_name = env.get("CLUSTER_NAME", "cp")

    print(f"head:    {facts['name']}  {facts['ip']}")
    print(f"network: {facts['network']}  subnets: {', '.join(facts['cidrs'])}")
    print(f"groups:  {', '.join(facts['security_groups'])}")
    print()
    nodes = existing_nodes(conn, cluster_name)
    if not nodes:
        print(f"no compute nodes tagged cluster={cluster_name}")
    else:
        print(f"{'NAME':<24} {'STATUS':<10} {'IP':<16} FLAVOR")
        for n in nodes:
            full = conn.compute.get_server(n.id)
            ip = server_ip(full, facts["network"]) or "-"
            fl = attr(full.flavor, "original_name") or attr(full.flavor, "name") or "?"
            print(f"{n.name:<24} {n.status:<10} {ip:<16} {fl}")
    print()
    show_sinfo()


def main():
    p = argparse.ArgumentParser(
        prog="cluster",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    up = sub.add_parser("up", help="create or scale compute nodes and wire up SLURM")
    up.add_argument(
        "--nodes", type=int, required=True, help="total number of compute nodes wanted"
    )
    up.add_argument(
        "--flavor",
        required=True,
        help="OpenStack flavor for compute nodes (see `cluster flavors`)",
    )
    up.add_argument(
        "--mem-spec-limit",
        type=int,
        metavar="MB",
        help="memory reserved for system use per node "
        "(default: 10%% of RealMemory, minimum 2048)",
    )
    up.set_defaults(func=cmd_up, needs_root=True)

    dn = sub.add_parser("down", help="delete this cluster's compute nodes")
    dn.add_argument("--yes", action="store_true", help="skip the confirmation prompt")
    dn.set_defaults(func=cmd_down, needs_root=True)

    st = sub.add_parser("status", help="show instances and sinfo")
    # Reads CLUSTER_NAME from the root-only cluster.env, so it needs sudo too.
    st.set_defaults(func=cmd_status, needs_root=True)

    fl = sub.add_parser(
        "flavors", help="list flavors and the memory each leaves for jobs"
    )
    fl.set_defaults(func=cmd_flavors)

    vol = sub.add_parser("volume", help="manage the shared /data volume")
    volsub = vol.add_subparsers(dest="volcmd", required=True)

    vl = volsub.add_parser("list", help="list volumes in this project")
    vl.set_defaults(func=cmd_volume_list)

    vc = volsub.add_parser("create", help="create a new volume")
    vc.add_argument("--size", type=int, required=True, metavar="GB")
    vc.add_argument("--name", help="default: <CLUSTER_NAME>-data")
    vc.set_defaults(func=cmd_volume_create, needs_root=True)

    va = volsub.add_parser(
        "attach",
        help="attach a volume and set it up as /data "
        "(formats only if blank), then export it over NFS",
    )
    va.add_argument("name")
    va.add_argument(
        "--force-format",
        action="store_true",
        help="erase an existing non-xfs filesystem. Destroys data.",
    )
    va.set_defaults(func=cmd_volume_attach, needs_root=True)

    vd = volsub.add_parser(
        "detach",
        help="unexport, unmount and detach the /data volume, so another can take its place",
    )
    vd.add_argument("name")
    vd.add_argument("--yes", action="store_true", help="skip the confirmation prompt")
    vd.add_argument(
        "--force", action="store_true", help="detach even while SLURM jobs are running"
    )
    vd.set_defaults(func=cmd_volume_detach, needs_root=True)

    fa = sub.add_parser("facts", help="print discovered cluster facts as shell vars")
    fa.set_defaults(func=cmd_facts)

    args = p.parse_args()
    if getattr(args, "needs_root", False) and os.geteuid() != 0:
        die("must run as root (use sudo)")
    try:
        args.func(args)
    except openstack.exceptions.SDKException as e:
        # A traceback here is noise: the useful thing to say is that `up` is
        # additive, so whatever it already created is kept and re-running
        # resumes rather than duplicating.
        die(
            f"OpenStack API error: {e}\n"
            f"       If this looks like a server-side hiccup (500, "
            f"DBConnectionError), just re-run.\n"
            f"       `cluster up` keeps what it already created and continues."
        )
    except KeyboardInterrupt:
        die("interrupted. Re-run `cluster up` to resume.")


if __name__ == "__main__":
    main()
