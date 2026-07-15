# Deploying on OpenStack (self-managed SLURM cluster)

Runbook for running this pipeline on a private OpenStack tenant with **instance/volume-only** access (no Magnum/Heat/Manila), no GPU, sharing one **Cinder volume**.

You create **one head node** in the Horizon dashboard. It builds everything else itself through the OpenStack API: the data volume, the compute nodes, the SLURM config and the NFS export.

It stands up a small SLURM cluster: one **head** node (slurmctld, Nextflow driver, NFS server exporting the volume) and N **compute** nodes (slurmd, Apptainer), all sharing `/data` over NFS. Runs with `-profile slurm` from [../nextflow.config](../nextflow.config).

`/data` holds:
- `<experiment>/`: one folder per experiment (e.g. `2025-W51/`), holding its own `input/` (raw images + `platemap.csv`), `results/`, and `.nextflow/` cache. You launch `nextflow run` from in here.
- `work/`: Nextflow's shared working directory
- `apptainer-cache/`: shared container images
- `.nextflow/`: `NXF_HOME`, the pulled pipeline copy + framework cache.

## Files here

| Path | Purpose |
|------|---------|
| `head.yaml.example` | Launch template. Copy to `head.yaml` (git-ignored) and fill it in. |
| `head-setup.sh`     | Idempotent head bootstrap. Fetched and run by the head. |
| `cluster.py`        | Cluster management. Installed on the head as the `cluster` command. |

**Secrets never go in a tracked file.** Your application credential goes only in `head.yaml`, which is git-ignored. `head.yaml.example` is tracked and must stay free of real values.

## Prerequisites

- Ubuntu **24.04** cloud image, an SSH keypair, and quota for 1 head + N compute instances, one Cinder volume, one security group.
- An **application credential** with a role that can create servers and volumes.

## Deploy

### 1. OpenStack: security group and application credential

*Network → Security Groups → Create* `cp-cluster`, then add rules:
- SSH (TCP 22), Remote = your IP `/32`.
- Remote = **security group** `cp-cluster`, all ports. The head reuses its own security groups for every compute node, so this rule is what lets them talk slurm/NFS/munge.

*Identity → Application Credentials → Create*:
- Give it the **`member`** role. `reader` cannot create servers and the build will fail.
- Set an expiry.
- Copy the ID and secret. The secret is shown once.

### 2. OpenStack: launch the head node

Make your own copy and fill it in. Edit the copy, never the tracked `.example`:

```bash
cd deploy
cp head.yaml.example head.yaml     # head.yaml is git-ignored
```

*Compute → Instances → Launch Instance*:
- **Details**: name = anything (e.g. `cp-head`). The head learns its own name.
- **Source**: Ubuntu 24.04, **Create New Volume = No**. It defaults to *Yes*, which boots the instance off a new Cinder volume, leaves the flavor's disk unused, and outlives the instance. It is **not** the `/data` volume.
- **Flavor**: the head runs the Nextflow driver and NFS, not jobs. Modest is fine.
- **Networks**: your tenant network. **Security Groups**: `cp-cluster`. **Key Pair**: yours. Your key gets propagated to every compute node, which is how you can SSH to them later.
- **Configuration → Customization Script**: paste your edited `head.yaml`.

The head boots and installs itself. **It creates nothing else**: no volume, no compute nodes. That is deliberate. Those choices are made on the head with the commands below, where you can see what is actually available and get errors immediately, instead of guessing at launch and then reading cloud-init logs to find out what went wrong.

### 3. Build the cluster from the head

```bash
ssh ubuntu@<head-floating-ip>
cloud-init status --wait                    # head finished installing

cluster flavors                             # memory each flavor leaves for jobs
cluster volume list                         # what volumes already exist?

sudo cluster volume create --size 100       # or reuse an existing one
sudo cluster volume attach cp-data          # sets up /data and exports it

sudo cluster up --nodes 8 --flavor m1.large # create nodes and wire up SLURM
sudo cluster status
```

Attach the volume before `cluster up`, so `/data` is exported by the time compute nodes first touch it. Compute nodes need no floating IP: the head reaches them on the tenant network.

## `cluster` command reference

Installed on the head as `/usr/local/bin/cluster`. Every command reads its credential from `/etc/cluster/cluster.env`, written from your `head.yaml` at launch.

| Command | Needs sudo | What it does |
|---|---|---|
| `cluster flavors` | no | Flavors and the memory each leaves for jobs |
| `cluster volume list` | no | Volumes in the project, and which are attachable |
| `cluster volume create` | **yes** | Create a new Cinder volume |
| `cluster volume attach` | **yes** | Attach a volume, set it up as `/data`, export it |
| `cluster up` | **yes** | Create or scale compute nodes, then wire up SLURM |
| `cluster status` | **yes** | Instances plus `sinfo` |
| `cluster down` | **yes** | Delete this cluster's compute nodes |
| `cluster facts` | no | Print discovered facts as shell vars (used by `head-setup.sh`) |

`sudo` is needed by anything that reads `CLUSTER_NAME` from `cluster.env`, which is root-only because it holds the application credential, plus anything that writes system state. `flavors` and `volume list` only talk to the API, so they run as `ubuntu`.

---

### `cluster flavors`

No arguments. Lists every flavor your credential can see, sorted by memory.

```text
NAME               VCPUS   RAM MB  DISK  EST JOB MEM
m1.small               2     4096    10         1779
m1.medium              4     8192    20         5657
m1.large              16    51200    40        43339
```

`RAM MB` is the flavor's nominal memory. `EST JOB MEM` is what is left for jobs after the kernel's cut and `MemSpecLimit`, and it is the only one of the two you can actually schedule against.

It is a deliberately conservative estimate, because no node exists yet to measure. `cluster up` measures a real booted node and configures from that instead.

A node must fit the **largest single job** you will submit, or that job pends forever however many nodes you add.

### `cluster volume list`

No arguments.

```text
NAME                          GB  STATUS      ATTACHED TO
cp-data                      100  available   -               <- attachable
old-results                  500  in-use      cp-head:/dev/vdb
```

Only `available` volumes can be attached. An `in-use` one must be detached from its current server first.

### `cluster volume create`

| Argument | Required | Default | Meaning |
|---|---|---|---|
| `--size GB` | **yes** | — | Volume size in gigabytes |
| `--name NAME` | no | `<CLUSTER_NAME>-data` | Volume name |

Creates the volume and waits for it to become `available`. Refuses if the name already exists, rather than making a second volume with a confusingly identical name. It does not attach it.

```bash
sudo cluster volume create --size 100
sudo cluster volume create --size 500 --name 2025-archive
```

### `cluster volume attach`

| Argument | Required | Default | Meaning |
|---|---|---|---|
| `NAME` | **yes** | — | Volume to attach (positional) |
| `--force-format` | no | off | Erase an existing non-xfs filesystem. **Destroys data.** |

Attaches the volume to the head, then makes it `/data`: formats if needed, mounts, creates `work/`, `apptainer-cache/`, `tmp/` and `.nextflow/`, writes `/etc/profile.d/cluster-tmp.sh`, and exports it over NFS to every CIDR the subnet can hand out.

**It never reformats a volume that holds data:**

| Volume contains | Default | With `--force-format` |
|---|---|---|
| xfs | mounted as-is | — |
| nothing | `mkfs.xfs` | — |
| ext4 / LVM / LUKS / anything else | **refuses** | wiped and reformatted |

It finds the device by watching for the one that appears after the attach, so a second volume landing on `/dev/vdc` works, and it mounts by filesystem UUID so a device rename across reboots cannot mount the wrong disk.

### `cluster up`

| Argument | Required | Default | Meaning |
|---|---|---|---|
| `--nodes N` | **yes** | — | Total compute nodes wanted, not how many to add |
| `--flavor NAME` | **yes** | — | Flavor for compute nodes (see `cluster flavors`) |
| `--mem-spec-limit MB` | no | 10% of `RealMemory`, min 2048 | Memory reserved per node for the system |

Creates compute nodes to match the head's own image, network and security groups, waits for them, measures one, then writes `slurm.conf` and `/etc/hosts` and starts the cluster.

`--nodes` is a **target**. It is idempotent and additive: with 4 nodes running, `--nodes 8` creates 4 more. It never deletes, so a lower number creates nothing. Gaps are filled by index, so if you deleted `cp-compute-2` by hand, the next run recreates that one rather than colliding with `cp-compute-3`.

`--mem-spec-limit` is subtracted from `RealMemory` when scheduling and reserves memory for the kernel, sshd, slurmd and the NFS client. Raise it if jobs on this cluster are known to use their full allocation and you want more headroom; lower it to squeeze out more schedulable memory.

```bash
sudo cluster up --nodes 8 --flavor m1.large
sudo cluster up --nodes 12 --flavor m1.large                     # add 4 more
sudo cluster up --nodes 8 --flavor m1.large --mem-spec-limit 6144
```

### `cluster status`

No arguments. Prints the head's own placement, the compute nodes with status/IP/flavor, and `sinfo`.

### `cluster down`

| Argument | Required | Default | Meaning |
|---|---|---|---|
| `--yes` | no | off | Skip the confirmation prompt |

Deletes only instances tagged `cluster=<CLUSTER_NAME>` **and** `role=compute`, so it can never touch the head or anything it did not create. Lists what it is about to delete and asks you to type the cluster name. `--yes` skips the prompt for scripts.

### `cluster facts`

No arguments. Prints discovered facts as shell variables, for `head-setup.sh` to `eval`. Useful for debugging what the head thinks it is on.

```text
CLUSTER_SELF_ID=e21b48ef-...
CLUSTER_HEAD_NAME=cp-head
CLUSTER_HEAD_IP=10.0.0.53
CLUSTER_NETWORK='common-computation-net'
CLUSTER_CIDRS='10.0.0.0/10'
```

## Changing SLURM config

`slurm.conf` lives **only on the head**. Compute nodes run `slurmd --conf-server <head>` and fetch it (configless), so there is no fan-out and no chance of nodes drifting out of sync:

```bash
sudo vim /etc/slurm/slurm.conf
sudo scontrol reconfigure
```

## Prepare an experiment folder

No clone needed: Nextflow pulls the pipeline straight from GitHub (`jakobhuuse/cell-paint-pipeline`) and resolves its bundled `conf/` from inside the pulled copy. Each experiment gets its own folder under `/data`, with raw images staged in an `input/` subfolder:

```text
/data/<experiment>/
    input/
        <batch-date>/<plate-id>/<TimePoint_x>/*.tif
        platemap.csv
    results/                        # created by the run
    .nextflow/                      # per-experiment cache + session state, enables -resume
```

Launch from inside the experiment folder, not the home directory.

## Run the pipeline

Stage raw images + `platemap.csv` into the experiment's `input/`, e.g. `rsync -av ./mydata/ ubuntu@<head-ip>:/data/2025-W51/input/`.

Run under **tmux** so the driver survives SSH disconnects:

```bash
tmux new -s <experiment>
cd /data/<experiment>

# DeepProfiler branch
nextflow run jakobhuuse/cell-paint-pipeline -profile slurm \
  --input_dir input

# CellProfiler branch
nextflow run jakobhuuse/cell-paint-pipeline -profile slurm \
  --pipeline cellprofiler --input_dir input
```

`workDir` is the shared `/data/work` with `cache = 'lenient'`, so `nextflow run ... -resume` from the same experiment folder cheaply re-uses completed tasks.

## Troubleshooting

### The head

- **No `cluster` command after boot**: the bootstrap never finished. `cloud-init status --long`, then `sudo tail -50 /var/log/cloud-init-output.log`. Most likely it could not fetch `CLUSTER_REPO`/`CLUSTER_REF`, or `head-setup.sh` refused because a `CHANGEME` placeholder was still in place, which means the `.example` got pasted instead of your filled-in `head.yaml`.
- **`cluster` exists but every command fails with 403 / "could not connect"**: the credential is wrong or expired. Note the head boots **fine** with a `reader` credential, because setup only reads. You find out at the first `volume create` or `up`. It needs the `member` role.
- **Re-running the head setup**: `sudo /opt/cluster/head-setup.sh` is idempotent and is how you recover a head that came up wrong. It will not regenerate the munge key or SSH key if they exist, so it will not orphan running compute nodes.

### Storage

- **No `/data` on the head**: nothing is attached yet. `cluster volume list`, then `sudo cluster volume attach NAME`. A `vda` larger than the flavor's disk means you booted the head from volume (**Create New Volume = Yes**); that volume is the root disk, not `/data`.
- **`cluster volume attach` refuses: "already holds a ext4 filesystem"**: working as intended. It will not format a volume that has data on it. Mount it by hand to keep it, or pass `--force-format` to erase it.
- **`/data` empty on compute nodes but fine on the head**: the NFS export does not cover the node's address. `sudo exportfs -v` on the head must list a subnet the node's IP falls inside. `sudo cluster volume attach NAME` re-runs the setup on an already-attached volume, which rewrites the export from the subnet the API reports.

### SLURM

- **Nodes `INVAL`, `Reason=Low RealMemory (reported:X < configured:Y)`**: SLURM rejects any node reporting less memory than `slurm.conf` claims. `cluster up` measures a node to avoid this, so you only see it after editing by hand. Set `RealMemory` at or below the reported number, then `sudo scontrol reconfigure`. No fan-out needed: the head holds the only copy.
- **Jobs stuck `PD` forever on healthy idle nodes**: the job asks for more than any node offers. `scontrol show job <id>` shows `Reason=Resources`; compare what it requested against `EST JOB MEM` from `cluster flavors`. No number of nodes fixes a job that fits on none of them.
- **`slurmd` never starts on a compute node**: it retries every 15s until the controller answers, so give it a minute. If it persists, `ssh ubuntu@<node>` (your key is on it) and check `systemctl status slurmd` and `journalctl -u slurmd`.
- **Nodes `down`/`drain`, "Munge decode failed"**: the node's munge key does not match the head's. `chrony` keeps clocks synced, so the usual cause is a node left over from a **previous head**: each head generates its own key. Delete and recreate them: `sudo cluster down && sudo cluster up --nodes N --flavor F`.

### Containers

- **`apptainer` not found after boot**: it is installed best-effort, and the PPA may lag a fresh Ubuntu release. Install the `.deb` from <https://github.com/apptainer/apptainer/releases>.
