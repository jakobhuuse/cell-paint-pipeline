# Deploying on OpenStack (self-managed SLURM cluster)

Runbook for running this pipeline on a private OpenStack tenant with **instance/volume-only**
access (no Magnum/Heat/Manila), over **SSH**, **no GPU**, instances ≤16 vCPU/50GB RAM sharing one
**Cinder volume**.

It stands up a small SLURM cluster: one **head** node (slurmctld, Nextflow driver, NFS server
exporting the volume) and N **compute** nodes (slurmd, Apptainer), all sharing `/data` over NFS.
Runs with `-profile slurm` from [../nextflow.config](../nextflow.config).

`/data` holds:
- `<experiment>/`: one folder per experiment (e.g. `2025-W51/`), holding its own `input/` (raw images
  + `platemap.csv`), `results/`, and `.nextflow/` cache. You launch `nextflow run` from in here.
- `work/`: Nextflow's shared working directory
- `apptainer-cache/`: shared container images
- `.nextflow/`: `NXF_HOME`, the pulled pipeline copy + framework cache, kept off the small root disk

## Files here

| Path | Purpose |
|------|---------|
| `head.yaml`        | Head-node boot config, one re-runnable setup script |
| `compute.yaml`     | Compute-node boot config, same pattern |
| `render.sh`        | Fills templates from `cluster.env` → paste-ready `*.local.yaml` |
| `cluster.env.example` | The values you set per cluster |

## Prerequisites

- Ubuntu **24.04** cloud image, an SSH keypair, and quota for 1 head + N compute instances, one
  Cinder volume, one security group.
- A tenant network shared by all instances. Note its **CIDR** (e.g. `10.0.0.0/24`).

Provisioning happens in the **Openstack dashboard** (no CLI/API needed). Everything after the VMs
exist is over SSH.

## Before you build the cluster: de-risk on one node

Validate on a single instance first. With no arguments it runs the bundled `tests/data` through the
default `deepprofiler` pipeline into `results/`, so nothing needs staging:

```bash
nextflow run jakobhuuse/cell-paint-pipeline -r v1.0.0 -with-apptainer
```

This confirms the images run **natively on x86-64** (no QEMU emulation, unlike Apple-Silicon dev).
Then run one real plate end-to-end for both `--pipeline` branches (pass `--input_dir <path>`) to get
a **DeepProfiler-on-CPU timing number** before committing hardware.

## Configure the cluster

`render.sh` fills the cloud-init templates from `cluster.env` and generates the shared munge key,
so you never hand-edit YAML or paste secrets.

**Before launching the head node:**

```bash
cd deploy
cp cluster.env.example cluster.env     # edit: HEAD_HOST, TENANT_CIDR, COMPUTE_NODES, CPUS, REAL_MEMORY, MEM_SPEC_LIMIT
./render.sh                            # -> head.local.yaml, compute.local.yaml (git-ignored)
```

**After the head boots:** read its internal IP from OpenStack, set `HEAD_IP` in `cluster.env`, then
re-run `./render.sh`. Only `compute.local.yaml` needs `HEAD_IP` (for its NFS mount and
`/etc/hosts` entry), so re-render before launching the compute nodes.

`CPUS`/`REAL_MEMORY`/`MEM_SPEC_LIMIT` in `cluster.env` must match the flavor you launch. There
are no defaults: `render.sh` refuses to run without them, and `cluster-setup.sh` refuses to run
without them too (RealMemory/MemSpecLimit are in MB, leave headroom under the flavor's total RAM).

For a different flavor on an already-running node, re-run the script by hand with new values,
no re-render needed:

```bash
sudo CPUS=32 REAL_MEMORY=98000 MEM_SPEC_LIMIT=10240 /usr/local/sbin/cluster-setup.sh
```

## Deploy

### 1. OpenStack: keypair, security group, volume

- *Compute → Key Pairs → Import Public Key*: your `~/.ssh/id_*.pub`.
- *Network → Security Groups → Create* `cp-cluster`, then add rules:
  - SSH (TCP 22), Remote = your IP `/32`.
  - Remote = security group `cp-cluster`, all ports. Lets nodes talk slurm/NFS/munge freely
    among themselves.
- *Volumes → Create Volume*: up to 80TB.

### 2. OpenStack: launch the head node

*Compute → Instances → Launch Instance*:
- **Details**: name = `head` (must equal `HEAD_HOST`).
- **Source**: Ubuntu 24.04. **Flavor**: your choice, matching `CPUS`/`REAL_MEMORY` in
  `cluster.env` (see Configure the cluster).
- **Networks**: tenant network. **Security Groups**: `cp-cluster`. **Key Pair**: yours.
- **Configuration → Customization Script**: paste `head.local.yaml`.

Once it boots, note its internal IP (Instances list) → set `HEAD_IP` in `cluster.env`. Then attach
your volume: *Instances → head → Attach Volume* (appears as `/dev/vdb`).

The boot script runs before the volume is attached, so `/data`/NFS aren't ready yet. Re-run the
idempotent setup script to pick it up:

```bash
ssh ubuntu@<head-ip>
cloud-init status --wait                 # first-boot script finished
sudo /usr/local/sbin/cluster-setup.sh    # now sees /dev/vdb → formats, mounts, exports /data
findmnt /data && sinfo
```

`cluster-setup.sh` is safe to re-run any time. It's how you recover a node that came up wrong, or
resize its resources after a flavor change (see Configure the cluster).

### 3. OpenStack: launch the compute nodes

Re-run `./render.sh` (now that `HEAD_IP` is set), then launch `compute-1 … compute-10` (matching
`COMPUTE_NODES=compute-[1-10]`) with the same image/security group/keypair, pasting
`compute.local.yaml` as the customization script. Each mounts `<head-ip>:/data` and registers with
the controller.

### 4. Register the compute nodes on the head

Compute IPs aren't known until boot, so add them to the head's `/etc/hosts` now (get each
instance's internal IP from the OpenStack Instances list), then restart slurmctld. A plain
`reconfigure` won't re-resolve addresses:

```bash
ssh ubuntu@<head-ip>
printf '10.0.0.11 compute-1\n10.0.0.12 compute-2\n...\n10.0.0.20 compute-10\n' | sudo tee -a /etc/hosts
sudo systemctl restart slurmctld
sinfo                 # nodes should show idle, not down/drain
srun -N1 hostname     # smoke-test job placement
```

If a node is `down`/`drain`: fix the cause (usually munge key mismatch or clock skew, see
Troubleshooting), then `sudo scontrol update nodename=compute-1 state=resume`.

### 5. Prepare an experiment folder

No clone needed: Nextflow pulls the pipeline straight from GitHub (`jakobhuuse/cell-paint-pipeline`)
and resolves its bundled `conf/` (the `.cppipe` files and DeepProfiler config/model) from inside
the pulled copy. Each experiment gets its own folder under `/data`, with the raw images staged in an
`input/` subfolder. You launch `nextflow run` from inside that folder, so its `results/` and
`.nextflow/` cache stay self-contained per experiment:

```text
/data/<experiment>/                 # e.g. /data/2025-W51, cd here to launch
    input/
        <batch-date>/<plate-id>/<TimePoint_x>/*.tif
        platemap.csv
    results/                        # created by the run
    .nextflow/                      # per-experiment cache + session state, enables -resume
```

```bash
ssh ubuntu@<head-ip>
mkdir -p /data/2025-W51/input
```

Launch from inside the experiment folder, not the home directory: Nextflow keeps its `.nextflow`
cache and session state in whatever directory you run it from (separate from the shared `workDir` at
`/data/work`), and that grows large over a long run, too large for the head's small root disk to
hold. `NXF_HOME` is already exported to `/data/.nextflow` by `cluster-setup.sh` (via
`/etc/profile.d/cluster-tmp.sh`), so the pulled pipeline copy and the framework cache stay on the
volume too.

The apptainer images pull on first use, so the first `nextflow run` will be slower while it fetches
and converts them into `/data/apptainer-cache`.

## Run the pipeline

Stage raw images + `platemap.csv` into the experiment's `input/`, matching the layout in `testdata/`:

```text
/data/2025-W51/input/<batch-date>/<plate-id>/<TimePoint_x>/*.tif
/data/2025-W51/input/platemap.csv
```

e.g. `rsync -av ./mydata/ ubuntu@<head-ip>:/data/2025-W51/input/` (or pull from Swift if reachable
internally).

Run under **tmux** so the driver survives SSH disconnects. `cd` into the experiment folder and pass
the paths relative to it (`--input_dir input --outdir results`):

```bash
tmux new -s 2025-W51
cd /data/2025-W51

# DeepProfiler branch
nextflow run jakobhuuse/cell-paint-pipeline -r v1.0.0 -profile slurm \
    --pipeline deepprofiler --input_dir input --outdir results

# CellProfiler branch (independent workflow)
nextflow run jakobhuuse/cell-paint-pipeline -r v1.0.0 -profile slurm \
    --pipeline cellprofiler --input_dir input --outdir results
```

`workDir` is the shared `/data/work` with `cache = 'lenient'`, so `nextflow run ... -resume` from the
same experiment folder cheaply re-uses completed tasks.

## Scale out

Boot more `computeN` instances, add their `/etc/hosts` line on the head, add their names to
`NodeName` in `/etc/slurm/slurm.conf` on **every** node, then `sudo scontrol reconfigure`.

**Faster:** after step 4, snapshot a configured compute node and boot future ones from it.
cloud-init still mounts `/data` and starts slurmd, but skips package installs.

## Troubleshooting

- **Any node came up wrong**: SSH in and run `sudo /usr/local/sbin/cluster-setup.sh`. It's
  idempotent: rewrites `slurm.conf`/`cgroup.conf`/munge key, fixes `/etc/hosts`, restarts daemons.
  Confirm with `scontrol ping` / `sinfo`.
- **`slurmd`: "DNS SRV lookup failed" / "failed to load configs"**. `/etc/slurm/slurm.conf` is
  missing, so slurmd fell back to configless mode (no SRV record here). Re-run the setup script.
- **`slurmctld`: `getaddrinfo() failed` / `address family '0' not supported`**. A node name
  didn't resolve at daemon start. Ensure `head` and every `computeN` are in `/etc/hosts`, then
  **restart** (not `reconfigure`, since addresses resolve only at start):
  `sudo systemctl restart slurmctld` (head) / `slurmd` (compute).
- **`scontrol reconfigure` → "Socket timed out"**: controller isn't answering. Run
  `sudo systemctl restart slurmctld`, then check `scontrol ping`.
- **Nodes `down`/`drain`, "Munge decode failed"**: munge keys differ, or clocks drifted. Re-run
  the setup script on the affected node. `chrony` keeps clocks synced.
- **`srun`/jobs hang `PD` (pending)**: check `scontrol show node computeX`. `RealMemory`/`CPUs`
  in `slurm.conf` must not exceed the flavor (over-spec drains the node). Re-run
  `cluster-setup.sh` with corrected `CPUS`/`REAL_MEMORY` env vars if they're wrong.
- **NFS permission errors**: all nodes default to the `ubuntu` user (uid 1000), so keep uids
  consistent if you add others. For more write throughput, `async` in `/etc/exports` trades crash
  durability for speed. `-resume` recovers work either way.
- **Apptainer cytotable `getuser()`/`.duckdb` error**: the slurm profile injects
  `--env USER=cytopipe,HOME=/tmp --no-home`. Verify with `nextflow config -profile slurm`.
- **`apptainer` not found after boot**: the PPA may lag a fresh Ubuntu release. Install the
  `.deb` from <https://github.com/apptainer/apptainer/releases> instead.
