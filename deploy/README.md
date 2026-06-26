# Deploying on OpenStack (self-managed SLURM cluster)

Runbook for running this pipeline on a private OpenStack tenant where you can manage **instances
and volumes only** (no Magnum/Heat/Manila admin), access is **SSH**, there is **no GPU**, and each
instance is ≤ 16 vCPU / 50 GB RAM with one shared **Cinder volume** ≤ 80 TB.

It stands up a small SLURM cluster: one **head** node (slurmctld + Nextflow driver + NFS server
exporting the volume) and N **compute** nodes (slurmd + Apptainer), all sharing `/data` over NFS.
The pipeline runs with `-profile slurm` from [../nextflow.config](../nextflow.config).

```
SSH ─► HEAD (slurmctld, nextflow, NFS server, /data on 80 TB Cinder vol)
            │ NFS /data  (identical path everywhere)
   COMPUTE1 … COMPUTEN  (slurmd, apptainer, 16 vCPU / 50 GB each)
```

`/data` holds `work/` (Nextflow), `apptainer-cache/`, `input/` (raw images + `platemap.csv`), `results/`.

## Files here

| Path | Purpose |
|------|---------|
| `cloud-init/head.yaml`        | Head-node boot config — installs everything via one re-runnable script |
| `cloud-init/compute.yaml`     | Compute-node boot config — same re-runnable script pattern |
| `cloud-init/render.sh`        | Fills the templates from `cluster.env` → paste-ready `*.local.yaml` (no API) |
| `cloud-init/cluster.env.example` | The handful of values you set per cluster |
| `slurm/slurm.conf.template`   | Reference SLURM config (also embedded in the cloud-init files) |
| `slurm/munge.key.example`     | How the shared munge secret is generated (the real key is git-ignored) |
| `apptainer/prefetch-images.sh`| Warm the shared image cache before the first run |

## Prerequisites

- An Ubuntu **24.04** cloud image, an SSH keypair, and quota for: 1 head + N compute instances,
  one ≤ 80 TB Cinder volume, one security group.
- A tenant (private) network all instances share; note its **CIDR** (e.g. `10.0.0.0/24`).

Provisioning is done in the **Horizon dashboard** (no OpenStack CLI/API needed); everything after
the VMs exist is over **SSH**. Each user works in their own Horizon login → their own project.

## Configure — render the cloud-init (no API)

`render.sh` fills the templates from a small `cluster.env` and generates the shared munge key, so
you never hand-edit YAML or paste secrets twice:

```bash
cd deploy/cloud-init
cp cluster.env.example cluster.env     # edit: HEAD_HOST, HEAD_IP, TENANT_CIDR, COMPUTE_NODES, COMPUTE_HOSTS
./render.sh                            # -> head.local.yaml, compute.local.yaml (git-ignored)
```

You don't know `HEAD_IP` until the head boots, so the usual order is: launch the head → read its
internal IP from Horizon → put it in `cluster.env` → `./render.sh` → launch compute nodes.
`CPUs=16 RealMemory=48000` in the templates assume the 16 vCPU / 50 GB flavor — adjust in
`head.yaml`/`compute.yaml` if yours differs (RealMemory in MB, leave headroom under total RAM).

## Step 1 — Horizon: keypair, security group, volume

- *Compute → Key Pairs → Import Public Key* — your `~/.ssh/id_*.pub`.
- *Network → Security Groups → Create* `cp-cluster`, then *Manage Rules → Add Rule*:
  - **SSH (TCP 22)** with Remote = CIDR `<your-ip>/32`.
  - A rule with **Remote = Security Group `cp-cluster`**, port range *all* — lets the nodes talk
    slurm (6817/6818), NFS (2049/111/mountd) and munge to each other without pinning ports.
- *Volumes → Volumes → Create Volume* — size up to 80 TB.

## Step 2 — Horizon: launch the head node

*Compute → Instances → Launch Instance*:
- **Details**: name = `head` (must equal `HEAD_HOST`).
- **Source**: Ubuntu 24.04 image. **Flavor**: your 16 vCPU / 50 GB.
- **Networks**: your tenant network. **Security Groups**: `cp-cluster`. **Key Pair**: yours.
- **Configuration → Customization Script**: paste `head.local.yaml`.

After it boots: note its **internal IP** (Instances list) → set `HEAD_IP` in `cluster.env`. Then
*Instances → head → Attach Volume* → attach your volume (it appears as `/dev/vdb`).

The boot script runs *before* the volume is attached, so `/data` + NFS aren't set up on the first
pass. Attach the volume, then **re-run the (idempotent) setup script** to pick it up:

```bash
ssh ubuntu@<head-ip>
cloud-init status --wait                 # first-boot script finished (slurmctld up)
sudo /usr/local/sbin/cluster-setup.sh    # now sees /dev/vdb → formats, mounts, exports /data
findmnt /data && sinfo
```

`cluster-setup.sh` is safe to re-run any time — it's how you recover a node that came up wrong
(it rewrites the configs/munge key and restarts the daemons) without relaunching it.

## Step 3 — Horizon: launch the compute nodes

`./render.sh` again (now that `HEAD_IP` is set) and launch the compute instances named
`compute-1 … compute-10` (matching `COMPUTE_NODES=compute-[1-10]`), same image/SG/keypair, pasting
`compute.local.yaml` as the customization script. Each mounts `<head-ip>:/data` and registers with
the controller.

## Step 4 — Register the compute nodes on the head

Compute IPs aren't known until they boot, so add them to the head's `/etc/hosts` now (render.sh
prints this exact line from your `COMPUTE_HOSTS`), then **restart** slurmctld so it resolves the new
addresses (a plain `reconfigure` does *not* re-resolve node addresses):

```bash
ssh ubuntu@<head-ip>
printf '10.0.0.11 compute-1\n10.0.0.12 compute-2\n...\n10.0.0.20 compute-10\n' | sudo tee -a /etc/hosts
sudo systemctl restart slurmctld
sinfo                 # nodes should show idle (not down/drain)
srun -N1 hostname     # smoke-test job placement
```

If a node is `down`/`drain`: `sudo scontrol update nodename=compute-1 state=resume` after fixing the
cause (usually munge key mismatch or clock skew — see Troubleshooting).

## Step 5 — Get the code and warm the image cache

On the head (the repo's `conf/` ships the `.cppipe` / DeepProfiler config + model, so cloning is
how those inputs land):

```bash
ssh ubuntu@<head-ip>
git clone https://github.com/jakobhuuse/cell-painting-pipeline.git
cd cell-painting-pipeline
./deploy/apptainer/prefetch-images.sh        # pulls the 4 images into /data/apptainer-cache
```

## Step 6 — Stage inputs and run

Put raw images + `platemap.csv` under `/data/input`, reproducing the layout from `testdata/`:

```text
/data/input/<batch-date>/<plate-id>/<TimePoint_x>/*.tif
/data/input/platemap.csv
```

Stage by SSH — e.g. from your machine: `rsync -av ./mydata/ ubuntu@<head-ip>:/data/input/`
(or pull from Swift on the head if your project has object storage reachable internally).

Run the driver under **tmux** so it survives SSH disconnects (it lives for the whole pipeline):

```bash
tmux new -s run
cd ~/cell-painting-pipeline

# DeepProfiler branch
nextflow run nextflow/workflows/deepprofiler.nf -profile slurm \
    --input_dir /data/input --outdir /data/results

# CellProfiler branch (independent workflow)
nextflow run nextflow/workflows/cellprofiler.nf -profile slurm \
    --input_dir /data/input --outdir /data/results
```

`workDir` is `/data/work` and `cache='lenient'` is set, so `nextflow run ... -resume` after an
interruption re-uses completed tasks cheaply.

## Step 7 — Scale out

Boot more `computeN` instances, add their `/etc/hosts` line on the head and their names to
`__COMPUTE_NODES__` in `/etc/slurm/slurm.conf` on **every** node, then `sudo scontrol reconfigure`.
**Faster:** after Step 4, snapshot a configured compute node and boot future ones from that
snapshot — cloud-init still mounts `/data` and starts slurmd, but skips package installs.

## Milestone 0 — single-node de-risk (do this first)

Before building the cluster, validate on **one** 16 vCPU / 50 GB instance with the volume attached
directly (no NFS) and Apptainer, using the default `local` executor:

```bash
nextflow run nextflow/workflows/deepprofiler.nf \
    -with-apptainer --input_dir /data/input --outdir /data/results   # or add a local apptainer profile
```

Run `testdata`, then **one real plate end-to-end** for both workflows. This confirms the images run
**natively on x86-64** (no QEMU emulation, unlike Apple-Silicon dev) and — critically — gives you
the **DeepProfiler-on-CPU timing number** to extrapolate before committing hardware.

> ⚠️ **No GPU is the throughput risk.** DeepProfiler's TF inference runs on CPU here — functional but
> potentially very slow at TB scale. If M0 timing is prohibitive, decide between: leaning on the
> CellProfiler-only workflow (CPU-native, scales cleanly), requesting a GPU flavor from your
> OpenStack admin, or accepting long wall-clock with wide scale-out across compute nodes.

## Troubleshooting

- **First move for any node that came up wrong:** SSH in and `sudo /usr/local/sbin/cluster-setup.sh`.
  It re-installs packages, rewrites `slurm.conf`/`cgroup.conf`/munge key, fixes `/etc/hosts`, and
  restarts the daemons — idempotent, no relaunch needed. Then `scontrol ping` / `sinfo` from the head.
- **`slurmd`: "DNS SRV lookup failed" / "failed to load configs"** — `/etc/slurm/slurm.conf` is
  missing, so slurmd fell back to *configless* mode (there's no SRV record). Re-run the setup script.
- **`slurmctld`: `getaddrinfo() failed` / `address family '0' not supported`** — a node name didn't
  resolve when the daemon started, leaving an empty address slot. Ensure `head` and every `computeN`
  are in `/etc/hosts` (DNS isn't relied on), then **restart** the daemon (not `reconfigure` — node
  addresses are resolved only at start): `sudo systemctl restart slurmctld` (head) / `slurmd` (compute).
- **`scontrol reconfigure` → "Socket timed out"** — the controller isn't answering; use
  `sudo systemctl restart slurmctld` instead and check `scontrol ping`.
- **Nodes `down`/`drain`, "Munge decode failed"** — munge keys differ or clocks drift. Re-run the
  setup script on the affected node so it gets the same key; `chrony` keeps clocks synced.
- **`srun`/jobs hang `PD` (pending)** — `scontrol show node computeX`; check `RealMemory`/`CPUs` in
  `slurm.conf` don't exceed the flavor (over-spec drains the node).
- **NFS permission errors** — all nodes use the default `ubuntu` user (uid 1000), so writes line up;
  if you added other users, keep uids consistent across nodes. For more write throughput on `/data`,
  consider `async` in `/etc/exports` (faster, weaker crash durability) — `-resume` recovers work.
- **Apptainer cytotable `getuser()`/`.duckdb` error** — the slurm profile injects
  `--env USER=cytopipe,HOME=/tmp --no-home`; verify it's in effect (`nextflow config -profile slurm`).
- **`apptainer` not found after boot** — the PPA may lag a fresh Ubuntu release; install the `.deb`
  from <https://github.com/apptainer/apptainer/releases> instead.
