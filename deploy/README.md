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

| Path                | Purpose                                                             |
| ------------------- | ------------------------------------------------------------------- |
| `head.yaml.example` | Launch template. Copy to `head.yaml` (git-ignored) and fill it in.  |
| `head-setup.sh`     | Idempotent head bootstrap. Fetched and run by the head.             |
| `cluster.py`        | Cluster management. Installed on the head as the `cluster` command. |

**Secrets never go in a tracked file.** Your application credential goes only in `head.yaml`, which is git-ignored. `head.yaml.example` is tracked and must stay free of real values.

## Prerequisites

- Ubuntu **26.04** cloud image, an SSH keypair, and quota for 1 head + N compute instances, one Cinder volume, one security group.
- An **application credential** with a role that can create servers and volumes.

## Deploy

### 1. OpenStack: security group and application credential

_Network → Security Groups → Create_ `cp-cluster`. Then _Manage Rules → Add Rule_ for each row below. All three are **Ingress** and **IPv4**.

| Rule       | Remote         | Value        | Why                                                                       |
| ---------- | -------------- | ------------ | ------------------------------------------------------------------------- |
| `SSH`      | CIDR           | `0.0.0.0/0`  | Reach the head. See the note below before narrowing this.                 |
| `ALL TCP`  | Security Group | `cp-cluster` | Slurm (6817/6818 plus ephemeral for `srun`) and NFS (2049) between nodes. |
| `ALL ICMP` | Security Group | `cp-cluster` | Optional. Lets you `ping` between nodes when debugging.                   |

The head reuses **its own** security groups for every compute node it creates, so the `cp-cluster`-to-`cp-cluster` rule is what lets the cluster talk to itself.

Narrow the SSH rule to your own address `/32` if your tenant hands out publicly routable floating IPs.

_Identity → Application Credentials → Create_:

- Give it the **`member`** role. `reader` cannot create servers and the build will fail.
- Set an expiry.
- Copy the ID and secret. The secret is shown once.

### 2. OpenStack: launch the head node

Make your own copy and fill it in. Edit the copy, never the tracked `.example`:

```bash
cd deploy
cp head.yaml.example head.yaml     # head.yaml is git-ignored
```

_Compute → Instances → Launch Instance_, then one row per tab of the wizard:

| Tab | Set |
|---|---|
| Details | Name: anything, e.g. `cp-head`. The head discovers its own name. |
| Source | Ubuntu 26.04, and **Create New Volume: No** |
| Flavor | Anything modest. The head runs the Nextflow driver and NFS, not jobs. |
| Networks | Your tenant network |
| Security Groups | `cp-cluster` |
| Key Pair | Yours |
| Configuration | Paste your edited `head.yaml` into **Customization Script** |

**Create New Volume** defaults to _Yes_, which boots the instance off a new Cinder volume, leaves the flavor's disk unused, and outlives the instance. That volume is **not** `/data`.

Your key pair is propagated to every compute node the head creates, which is how you SSH to them later. Compute node flavors are chosen separately, with `cluster up`.

The head boots and installs itself. **It creates nothing else**. That is deliberate. Those choices are made on the head with the commands below, where you can see what is actually available and get errors immediately, instead of guessing at launch and then reading cloud-init logs to find out what went wrong.

### 3. Build the cluster from the head

Wait for the instance to boot, associate a floating IP, then:

```bash
ssh ubuntu@<head-floating-ip>               # If the connection refuses, wait
cloud-init status --wait                    # head finished installing (may take some time)

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

| Command                 | Needs sudo | What it does                                                   |
| ----------------------- | ---------- | -------------------------------------------------------------- |
| `cluster flavors`       | no         | Flavors and the memory each leaves for jobs                    |
| `cluster volume list`   | no         | Volumes in the project, and which are attachable               |
| `cluster volume create` | **yes**    | Create a new Cinder volume                                     |
| `cluster volume attach` | **yes**    | Attach a volume, set it up as `/data`, export it               |
| `cluster up`            | **yes**    | Create or scale compute nodes, then wire up SLURM              |
| `cluster status`        | **yes**    | Instances plus `sinfo`                                         |
| `cluster down`          | **yes**    | Delete this cluster's compute nodes                            |
| `cluster facts`         | no         | Print discovered facts as shell vars (used by `head-setup.sh`) |

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

### `cluster volume detach`

| Argument | Required | Default | Meaning |
|---|---|---|---|
| `NAME` | **yes** | — | Volume to detach (positional) |
| `--yes` | no | off | Skip the confirmation prompt |
| `--force` | no | off | Detach even while SLURM jobs are running |

Unexports `/data`, unmounts it, drops its `fstab` entry, and detaches the volume, leaving it `available`. Use it to swap `/data` onto a different volume:

```bash
sudo cluster volume detach cp-data
sudo cluster volume attach cp-data-2
```

Order matters and the command handles it: `nfsd` holds a reference to the filesystem, so unmounting before unexporting fails with "target is busy". If the unmount still fails it reports what is holding `/data` rather than doing a lazy unmount, which would hide the problem instead of fixing it.

It refuses while SLURM jobs are running, since every one of them can be using `/data`. It also removes the `fstab` line, without which the next boot blocks trying to mount a volume that is no longer there. Compute nodes are told to remount afterwards, because their NFS handle goes stale the moment `/data` changes underneath them.

To grow storage you do not need any of this. Extend the volume in place instead: `openstack volume set --size <bigger> cp-data && sudo xfs_growfs /data`.

### `cluster volume create`

| Argument      | Required | Default               | Meaning                  |
| ------------- | -------- | --------------------- | ------------------------ |
| `--size GB`   | **yes**  | —                     | Volume size in gigabytes |
| `--name NAME` | no       | `<CLUSTER_NAME>-data` | Volume name              |

Creates the volume and waits for it to become `available`. Refuses if the name already exists, rather than making a second volume with a confusingly identical name. It does not attach it.

```bash
sudo cluster volume create --size 100
sudo cluster volume create --size 500 --name 2025-archive
```

### `cluster volume attach`

| Argument         | Required | Default | Meaning                                                  |
| ---------------- | -------- | ------- | -------------------------------------------------------- |
| `NAME`           | **yes**  | —       | Volume to attach (positional)                            |
| `--force-format` | no       | off     | Erase an existing non-xfs filesystem. **Destroys data.** |

Attaches the volume to the head, then makes it `/data`: formats if needed, mounts, creates `work/`, `apptainer-cache/`, `tmp/` and `.nextflow/`, writes `/etc/profile.d/cluster-tmp.sh`, and exports it over NFS to every CIDR the subnet can hand out.

It also sizes the nfsd thread pool, in `/etc/nfs.conf.d/threads.conf`. The stock 8 threads is the usual reason `/data` feels slow once the whole cluster is on it, since every node's traffic queues behind those 8. If it warns that nfsd is running a different number than configured, `rpc.nfsd` was already up and only reads its config at startup: `sudo systemctl restart nfs-kernel-server` applies it. Compute nodes mount `hard`, so they block and retry across the restart rather than erroring.

**The export is `async`,** meaning `nfsd` acknowledges a write once it is in the head's page cache rather than once it is on the volume. This is a large speedup for the work directory's constant small creates, renames and unlinks, and it is safe because nothing irreplaceable is written through the export. Export options only govern how `nfsd` answers its clients, and your input images never reach `nfsd`: they are rsynced to the head and written to local XFS, and Nextflow publishes results from the driver, which also runs on the head. Everything a compute node writes over NFS is scratch (`work/`, `tmp/`, `apptainer-cache/`) and re-derivable by re-running.

The tradeoff is that a head crash can lose already-acknowledged writes without the client being told. **After a head crash, re-run from scratch rather than with `-resume`**, since a resumed run can reuse a work-directory file that was silently truncated.

**Tuning the thread pool.** `NFSD_THREADS` in `cluster.py` is a starting point sized for the number of clients, not a derived answer. Threads are cheap to over-provision, since idle ones are sleeping kernel threads blocked on I/O rather than burning CPU, so they do not meaningfully compete with `slurmctld` or the Nextflow driver. Under-provisioning just makes requests queue. Check it under real load:

```bash
cat /proc/fs/nfsd/pool_stats   # pool packets-arrived sockets-enqueued threads-woken threads-timedout
```

A `sockets-enqueued` that climbs during a run means requests arrived with no thread free, so raise the count. A large `threads-timedout` with `sockets-enqueued` near zero means there are more threads than the load needs, which is harmless. Ignore the `th` line in `/proc/net/rpc/nfsd`: every field after the thread count has been hardcoded to zero since kernel 2.6.29, so it looks like an idle server no matter how loaded it is.

**It never reformats a volume that holds data:**

| Volume contains                   | Default       | With `--force-format` |
| --------------------------------- | ------------- | --------------------- |
| xfs                               | mounted as-is | —                     |
| nothing                           | `mkfs.xfs`    | —                     |
| ext4 / LVM / LUKS / anything else | **refuses**   | wiped and reformatted |

It finds the device by watching for the one that appears after the attach, so a second volume landing on `/dev/vdc` works, and it mounts by filesystem UUID so a device rename across reboots cannot mount the wrong disk.

### `cluster up`

| Argument              | Required | Default                       | Meaning                                          |
| --------------------- | -------- | ----------------------------- | ------------------------------------------------ |
| `--nodes N`           | **yes**  | —                             | Total compute nodes wanted, not how many to add  |
| `--flavor NAME`       | **yes**  | —                             | Flavor for compute nodes (see `cluster flavors`) |
| `--mem-spec-limit MB` | no       | 10% of `RealMemory`, min 2048 | Memory reserved per node for the system          |

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

| Argument | Required | Default | Meaning                      |
| -------- | -------- | ------- | ---------------------------- |
| `--yes`  | no       | off     | Skip the confirmation prompt |

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
- **Getting a shell on a compute node**: from the head, `ssh cp-compute-3`. No sudo, no agent forwarding, no `-i`. Compute nodes have no floating IP, so this only works from the head, which is also the only place the key lives.
- **A node answers SSH with "Please login as the user ubuntu rather than the user root"**: that node predates the fix below and its copy of *your* key is booby-trapped. Use `ssh cp-compute-N`, which uses the head's key instead and is unaffected. `cluster up` used to copy `/root/.ssh/authorized_keys` from the head verbatim onto each node's `ubuntu` account, and on an Ubuntu cloud image your key sits in root's file behind a forced command that prints exactly that line and hangs up. Nodes created now get a stripped key. Existing nodes keep the bad entry until rebuilt.
- **`slurmd` never starts on a compute node**: it retries every 15s until the controller answers, so give it a minute. If it persists, `ssh cp-compute-N` and check `systemctl status slurmd` and `journalctl -u slurmd`.
- **Nodes `down`/`drain`, "Munge decode failed"**: the node's munge key does not match the head's. `chrony` keeps clocks synced, so the usual cause is a node left over from a **previous head**: each head generates its own key. Delete and recreate them: `sudo cluster down && sudo cluster up --nodes N --flavor F`.

### Containers

- **`apptainer` not found after boot**: it is installed best-effort, and the PPA may lag a fresh Ubuntu release. Install the `.deb` from <https://github.com/apptainer/apptainer/releases>.
