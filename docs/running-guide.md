# Running the pipeline

Back to [README](../README.md).

Nextflow needs a Unix-like environment. It runs natively on macOS and Linux. On Windows it needs WSL, which Path B below sets up for you as its first step, an optional step that only applies if you're on Windows. Path A skips your own machine entirely and runs everything on a remote SLURM cluster, that route works the same regardless of which OS you're on, since all you need locally is an SSH client.

## Pick your path

**Path A, run it on a SLURM cluster (recommended for real experiments).** You connect over the network and everything runs there. Your machine only sends files and watches progress. Best for real experiments and large datasets.

**Path B, run it on your own machine.** A one-time setup installs Docker (plus WSL2 first, if you're on Windows). Best for trying the pipeline out, small test datasets, or when you don't have cluster access. You can run real experiments this way, but it obviously won't run as fast as on a SLURM cluster.

## Words you'll run into

- **Nextflow**, the tool that drives the pipeline. You give it one command and it runs every processing step in the right order.
- **WSL (Windows Subsystem for Linux)**, Windows' built-in way to run a real Linux environment alongside Windows. Nextflow needs one, since it doesn't run natively on Windows. Path B's first setup step below sets it up for you if you don't already have it.
- **Pipeline branch**, which set of tools does the feature extraction, `deepprofiler` (a deep-learning model, the default), `cellprofiler` (classical image measurements), and `qc` (quality control). Choose with `--pipeline`.
- **Container (Docker / Apptainer)**, a sealed, ready-made copy of CellProfiler, DeepProfiler, and the rest, so you never install that software yourself.

## Before you start (both paths)

Have these ready regardless of which path you take.

- Your images, `.tif` files, organized in one folder per plate.
- A `platemap.csv` sitting directly alongside those plate folders, mapping wells to compounds.
- A decision on which branch to run, `deepprofiler` (default, benefits from running on a GPU) or `cellprofiler` (CPU-only, classical measurements).

Expected layout.

```text
my_experiment/
    platemap.csv
    2026-01-15/
        26159/               # one plate's .tif images live in here
        26159/TimePoint_1/   # or, if your scope exports one folder per timepoint, one level deeper
        26160/               # each plate gets its own folder either way
```

The pipeline looks for `.tif` files anywhere inside each plate folder, so a `TimePoint_1` subfolder (or several, one per timepoint) works with no extra setup, nothing to change on the command line for that.

`--input_dir` can point at any level of this layout, the experiment folder shown above (all dates, all plates), a single date folder (all plates for that date), or a single plate folder (just that plate).

The pipeline works out which level you gave it by looking for `platemap.csv`, which always sits at the experiment root. It checks `--input_dir` itself, then its parent folder, then its grandparent, and whichever one actually has `platemap.csv` tells it how many levels to descend to reach plate folders. So `platemap.csv` needs to sit at the experiment root either way, no more than two folders above wherever you point `--input_dir`, or the pipeline errors out rather than guessing.

Any other folders mixed in alongside the dates or plates, e.g. a `results/` folder from a previous run, get dropped automatically too, since they end up with no `.tif` images once the pipeline looks inside them.

`platemap.csv` itself needs a specific shape, a plain comma-separated CSV, one row per well, with these columns present:

- `Metadata_PlateID`, matching a plate folder's name exactly (e.g. `26159`), so the pipeline knows which rows belong to which plate.
- `Metadata_DestinationWell`, the well ID (e.g. `A02`) each row describes. Each plate/well combination must appear only once, a well listed twice on the same plate is treated as an error rather than guessed at.
- `Metadata_Compound`, the compound (or `DMSO` for controls) in that well. Both branches rely on this, DMSO wells are how the pipeline finds its normalization controls.
- `Metadata_Batch`, a batch/synthesis identifier for that well (used by the `deepprofiler` branch).

Any other columns, `Metadata_` prefixed or not, are welcome and just ride along as extra annotation. Leading/trailing whitespace in headers and cells is stripped automatically, and a leading BOM (common when a spreadsheet program saves the file) is handled too, so exporting from Excel or Google Sheets is fine.

## Setup

Do this section once, then jump to [Running](#running) whenever you actually want to process data. Path A's setup is mostly a one-time-per-experiment-folder thing, Path B's is mostly a one-time-per-machine thing, see each subsection.

### Path A setup (SLURM cluster)

Nothing is installed on your own machine beyond an SSH program, both Windows and macOS/Linux already ship one.

Before you begin, get these from whoever manages your cluster (your PI, IT, or the person who set it up).

- The cluster's head node address, e.g. `203.0.113.42` (`<head-ip>` below).
- Your login username (usually `ubuntu`) and either a password or an SSH key file they give you.
- A name for your experiment folder, e.g. `my_experiment`.
- Whether your image data is already reachable from the cluster over the network, and if so, the path to it. If not, you'll copy the data across instead, see step 5 below.

1. **Open a terminal.** On Windows, press Start, type `PowerShell`, and open it, Windows 10/11 ships an SSH client built in. On macOS or Linux, open your normal Terminal app, it already has one too.

2. **Connect to the cluster.**

   ```bash
   ssh ubuntu@<head-ip>
   ```

   Type `yes` if asked to trust the head node the first time, then enter your password. If you were given a key file, connect with `ssh -i /path/to/key.pem ubuntu@<head-ip>` instead (`ssh -i C:\path\to\key.pem ubuntu@<head-ip>` on Windows).

3. **Create a folder for this experiment.** Still connected over SSH. Replace `<my_experiment>` with the experiment's name. This is where results will land, whether or not your images end up living here too.

   ```bash
   mkdir -p /data/<my_experiment>
   ```

4. **Point at your data directly, no copying needed (the default).** If your images already sit somewhere the cluster can reach, as in the last bullet above, that's all you need, `--input_dir` can point straight at that path when you run the pipeline later (see [Running > Path A](#path-a-running-slurm-cluster)). Confirm you can actually read it first.

   ```bash
   ls /path/to/the/network/location
   ```

   If this works, skip step 5 below, it's only needed as a backup, and carry on to step 6.

5. **(Backup, if step 4 doesn't apply, or your connection is too unstable to rely on for the whole run) Copy your data across instead.** Open a second, separate terminal window on your own machine (leave the first one connected) and run.

   ```bash
   mkdir -p /data/<my_experiment>/input
   ```

   ```powershell
   # Windows (PowerShell)
   scp -r C:\Users\you\Desktop\my_experiment\* ubuntu@<head-ip>:/data/<my_experiment>/input/
   ```

   ```bash
   # macOS / Linux
   scp -r ~/Desktop/my_experiment/* ubuntu@<head-ip>:/data/<my_experiment>/input/
   ```

   If typing file paths feels error-prone, a graphical alternative works just as well, [WinSCP](https://winscp.net/) on Windows, [Cyberduck](https://cyberduck.io/) on macOS. Both let you drag and drop your plate folders and `platemap.csv` onto the cluster through a two-pane window, like copying files between two folders in File Explorer or Finder.

   This can take a while for a full plate of images, let it finish before moving on. Once it's done, `--input_dir input` (relative to your experiment folder) is what you'll point the run at later, instead of a network path.

6. **Start a session that survives disconnects.** Back in your first window (the one connected over SSH).

   ```bash
   tmux new -s my_experiment
   ```

   Everything you type after this keeps running even if your machine sleeps or loses Wi-Fi. If you get disconnected, reconnect with step 2 above, then run `tmux attach -t my_experiment` to get back to where you left off.

7. **Move into your experiment folder.**

   ```bash
   cd /data/my_experiment
   ```

### Path B setup (your own machine)

A one-time setup, needs administrator rights on the machine and about 20 GB of free disk space.

A laptop can comfortably run the bundled test images or a handful of wells. A full plate, especially on the `deepprofiler` branch which wants a GPU, is realistically a job for Path A. Treat this path as "try it out," not "process my real experiment."

1. **(Windows only) Set up WSL2 first.** Nextflow needs a Unix-like environment, and Windows doesn't ship one on its own. Press Start, type `PowerShell`, right-click it and choose "Run as administrator," then run.

   ```powershell
   wsl --install
   ```

   Restart the PC when it asks. This installs both WSL2 and a bundled Ubuntu Linux system. After restarting, open "Ubuntu" from the Start menu, on first launch it asks you to pick a username and password for this Linux environment, any values are fine, just remember them. Every step below happens inside that Ubuntu terminal, not PowerShell.

   If you're on macOS or Linux, skip this step entirely, you already have a native terminal that works, open it and continue below.

2. **(Windows only, if needed) Give WSL more resources.** WSL2 caps itself at half your machine's RAM by default, and doesn't hand over extra CPU cores either. That's fine for the bundled sample data, but a real experiment's CellProfiler/DeepProfiler containers can want more of both. If your machine has 16 GB of RAM or more, it's worth raising these caps now, before they become a problem. If you're just trying the bundled sample data, or your machine is lighter on resources, skip this for now, you can always come back to it if a real run later fails with what looks like an out-of-memory error, or runs slower than expected.

   Create (or edit) a file named `.wslconfig` in your Windows user folder, `C:\Users\you\.wslconfig`.

   ```ini
   [wsl2]
   memory=16GB
   processors=4
   ```

   Adjust both numbers to whatever you can spare, leaving a couple of CPU cores and a few GB of RAM free for Windows itself.

   On a network with a corporate proxy or VPN, WSL can otherwise struggle to reach the internet at all (pulling container images, reaching GitHub for the Nextflow installer). If you hit connection failures during the steps below, add these to the same `[wsl2]` section too.

   ```ini
   networkingMode=mirrored
   dnsTunneling=true
   autoProxy=true
   ```

   Only add these if you actually see connection problems, they change how WSL's networking behaves and most setups don't need them.

   Apply any `.wslconfig` change from PowerShell.

   ```powershell
   wsl --shutdown
   ```

   Reopen "Ubuntu" from the Start menu afterward, it comes back up with the new settings. Docker Desktop also needs its own WSL integration switched on for these resource limits to actually reach the containers it runs, that's covered in the next step.

3. **Install Docker.** On Windows, download and install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/), keep "Use WSL 2 based engine" checked during setup (it's the default), then open Docker Desktop, Settings, Resources, WSL Integration, and switch on integration with the Ubuntu distro. On macOS, install [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/). On Linux, install [Docker Engine](https://docs.docker.com/engine/install/) for your distribution.

4. **Install Java and Nextflow.** On Windows, open the "Ubuntu" app from the Start menu to get back into your WSL terminal (or type `wsl` into PowerShell, which drops you into the same place). Nextflow needs Java to run, and it isn't installed by anything above yet.

   ```bash
   # Windows (inside the Ubuntu/WSL terminal) and Linux
   sudo apt update && sudo apt install -y default-jre
   curl -s https://get.nextflow.io | bash
   sudo mv nextflow /usr/local/bin/
   ```

   ```bash
   # macOS
   brew install openjdk
   curl -s https://get.nextflow.io | bash
   sudo mv nextflow /usr/local/bin/
   ```

5. **Check everything works.**

   ```bash
   nextflow -version
   docker run hello-world
   ```

   The second command should print a short "Hello from Docker!" message. If it instead complains it can't connect, open Docker Desktop (Windows/macOS) or start the Docker service (`sudo systemctl start docker` on Linux) and make sure it's running.

6. **Create a folder for this experiment, no need to copy your data in.**

   ```bash
   mkdir -p ~/my_experiment
   ```

### Finding and mounting a network file share (optional)

If your images live on a network file share rather than your own machine's disk, here's how to find and connect to one, then point `--input_dir` at wherever it appears (see the file-share examples in [Running > Path B](#path-b-running-your-own-machine)).

Ask whoever manages your data (your PI, IT, or the person who set it up) for the share's address. It typically looks like `\\fileserver.example.org\shared\my-project` on Windows, or `smb://fileserver.example.org/shared/my-project` on macOS/Linux.

**Windows.** Open File Explorer, right-click "This PC" in the sidebar and choose "Map network drive" (on newer Windows, use the "..." menu near the top instead). Pick a free drive letter, e.g. `Z:`, paste in the share's address, check "Reconnect at sign-in" if you'll use it regularly, and enter your credentials if asked. Once mapped, it shows up as `Z:\` in Windows, and as `/mnt/z/` from inside WSL, the same pattern as the local `C:` drive already used elsewhere in this guide.

**macOS.** In Finder, press `Cmd+K` ("Go", "Connect to Server"), paste in the share's address, and connect. It mounts under `/Volumes/`.

**Linux.** Mount it with whatever CIFS/SMB or NFS tools your distribution provides, ask your IT for the exact options your particular share needs.

### Inspecting files with VSCode (optional)

[VSCode](https://code.visualstudio.com/) is a good way to browse the experiment folder, check `platemap.csv`, and look through results without living entirely in a terminal. Install it, then connect it to wherever your files actually live, that differs by path.

**Path A.** Install the "Remote - SSH" extension, open the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`), search for "Remote-SSH" and pick the option to connect to a host, then enter `ubuntu@<head-ip>` (the same address and login from [Setup > Path A](#path-a-setup-slurm-cluster)). Once connected, open `/data/my_experiment`.

**Path B, Windows.** Install the "WSL" extension, then from inside your Ubuntu/WSL terminal (the one Setup > Path B has you working in), run.

```bash
code ~/my_experiment
```

VSCode opens connected to that WSL folder directly, no separate connection step needed.

**Path B, macOS/Linux.** No extra extension needed. Run `code ~/my_experiment` from your terminal, or open the folder directly from inside VSCode (File, Open Folder) if the `code` command isn't set up.

## Running

### Adjusting parameters

Every command below sets the same three flags, in the same order, `--pipeline` (which of `deepprofiler`, `cellprofiler`, or `qc` to run), `--input_dir` (where your images and `platemap.csv` are), and `--outdir` (where results land). A few more flags show up further down, always right where they first become relevant, `--profiling false` for a fast first test, `--qc_exclude_file` if you use the QC review workflow below, and so on, tacked on after the same three core flags rather than mixed in among them. Everything else keeps a sensible default, but you can override any parameter the same way, by adding `--name value` to the `nextflow run` command. The full list, grouped by tool, is documented in [docs/parameters.md](parameters.md).

### Reviewing image quality first (optional)

Before running `deepprofiler` or `cellprofiler` on a new dataset, it's worth running the `qc` pipeline first to check for blurry or otherwise bad images. Swap `--pipeline` to `qc` on the exact same command you'd otherwise run (same `-profile`, `--input_dir`, `--outdir`).

```bash
nextflow run jakobhuuse/cell-paint-pipeline -profile standard \
    --pipeline qc --input_dir /path/to/my_experiment --outdir results
```

This publishes one combined `results/qc/gallery.html` covering every plate in the run. Open it in a browser, it shows every image's thumbnail next to its per-channel focus-blur value, with a min/max box per channel that highlights out-of-range images live as you type. Once you've settled on bounds that catch the bad images, click "Download exclusion list" to save an `excluded.csv`.

Point the real run at that file with `--qc_exclude_file`, alongside whichever `--pipeline` you actually want to run.

```bash
nextflow run jakobhuuse/cell-paint-pipeline -profile standard \
    --pipeline cellprofiler --input_dir /path/to/my_experiment --outdir results \
    --qc_exclude_file /path/to/excluded.csv
```

Excluded images are dropped before feature extraction (and, on the `deepprofiler` branch, before nuclei segmentation too). This step is entirely optional. Skipping it (the default `--qc_exclude_file` is an empty list) runs exactly as before.

### Path A running (SLURM cluster)

Picks up from [Setup > Path A](#path-a-setup-slurm-cluster) above, connected over SSH and sitting inside your experiment folder.

1. **Run the pipeline on your data.**

   ```bash
   # Default, pointing straight at the network location from Setup > Path A, step 4
   nextflow run jakobhuuse/cell-paint-pipeline -profile slurm \
       --pipeline deepprofiler \
       --input_dir /path/to/the/network/location --outdir results
   ```

   ```bash
   # If you copied your data in instead (Setup > Path A, step 5)
   nextflow run jakobhuuse/cell-paint-pipeline -profile slurm \
       --pipeline deepprofiler \
       --input_dir input --outdir results
   ```

   Swap `--pipeline deepprofiler` for `--pipeline cellprofiler` to use the other branch. This is the command that does the real work, expect it to run for a while on a full plate.

2. **Step away safely.** Detach from the session with `Ctrl+B` then `D` (do **NOT** press `Ctrl+D`, this shuts down the session). Close your terminal, disconnect Wi-Fi, whatever you need. Reconnect any time with `ssh ubuntu@<head-ip>` then `tmux attach -t my_experiment` to check on it.

3. **Collect your results.** Once Nextflow prints `Completed successfully`, results sit in `/data/my_experiment/results/` on the cluster. Pull them back the same way you sent images over, in reverse, with `scp` or a graphical tool.

   ```powershell
   # Windows (PowerShell)
   scp -r ubuntu@<head-ip>:/data/my_experiment/results C:\Users\you\Desktop\my_experiment\
   ```

   ```bash
   # macOS / Linux
   scp -r ubuntu@<head-ip>:/data/my_experiment/results ~/Desktop/my_experiment/
   ```

### Path B running (your own machine)

Picks up from [Setup > Path B](#path-b-setup-your-own-machine) above, with Docker, Java, and Nextflow installed and your experiment folder created.

1. **Do a quick test run first.** Confirm the setup works end-to-end using the pipeline's small bundled sample data before trying your own.

   ```bash
   nextflow run jakobhuuse/cell-paint-pipeline -profile standard --pipeline cellprofiler --profiling false
   ```

   `--profiling false` stops after the raw per-cell measurements. The bundled sample data doesn't have enough wells for the cohort statistics profiling needs, so this sidesteps that failing on a quick test (more on this in [If something goes wrong](#if-something-goes-wrong)). This command also pulls a few container images the first time, so expect it to take longer on the first run than later ones.

2. **Run it on your own data.**

   ```bash
   # Windows, /mnt/c/... is how Ubuntu sees your Windows C: drive, point straight at it.
   cd ~/my_experiment
   nextflow run jakobhuuse/cell-paint-pipeline -profile standard \
       --pipeline cellprofiler \
       --input_dir /mnt/c/Users/you/Desktop/my_experiment --outdir results
   ```

   ```bash
   # macOS / Linux, point straight at wherever your files already are.
   cd ~/my_experiment
   nextflow run jakobhuuse/cell-paint-pipeline -profile standard \
       --pipeline cellprofiler \
       --input_dir ~/Desktop/my_experiment --outdir results
   ```

   From a network file share, map or mount it first, then point `--input_dir` at wherever it shows up, the run command itself doesn't change.

   ```bash
   # Windows, after mapping the share to a drive letter (e.g. Z:) in File Explorer,
   # WSL sees it the same way it sees your local C: drive, under /mnt/.
   nextflow run jakobhuuse/cell-paint-pipeline -profile standard \
       --pipeline cellprofiler \
       --input_dir /mnt/z/my_experiment --outdir results
   ```

   ```bash
   # macOS / Linux, after mounting the share (e.g. under /Volumes/share on macOS,
   # or /mnt/share on Linux after `mount -t cifs //server/share /mnt/share ...`).
   nextflow run jakobhuuse/cell-paint-pipeline -profile standard \
       --pipeline cellprofiler \
       --input_dir /mnt/share/my_experiment --outdir results
   ```

   If you have an NVIDIA GPU, swap `-profile standard` for `-profile gpu` to speed up the `deepprofiler` branch. On Windows it needs the [NVIDIA CUDA driver for WSL](https://docs.nvidia.com/cuda/wsl-user-guide/index.html) installed first. On Linux it needs the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html). Apple Silicon and AMD Macs have no NVIDIA GPU, so this option doesn't apply there. Treat it as optional either way.

3. **Find your results.** On Windows, results land in `~/my_experiment/results/` inside Ubuntu. Browse them with Windows File Explorer by running `explorer.exe .` from inside that folder in the Ubuntu terminal, or by typing `\\wsl$\Ubuntu\home\<your-username>\my_experiment\results` into an Explorer address bar. On macOS or Linux, results already sit directly in `~/my_experiment/results/`, open it with your normal file manager or `open .` (macOS) / `xdg-open .` (Linux).

### Reading the results

Everything lands under `results/<pipeline>/`, named after whichever branch you ran, so a `deepprofiler` run, a `cellprofiler` run, and a `qc` run never overwrite each other.

| Folder                    | What's in it                                                              |
| ------------------------- | ------------------------------------------------------------------------- |
| `raw/`                    | One row of measurements per cell, before any averaging.                   |
| `normalized/`             | The same measurements, adjusted against your DMSO control wells.          |
| `<pipeline>/` (top level) | The final table, one row per compound, plus QC report figures.            |

Ran `--pipeline qc`? `results/qc/gallery.html` covers every plate in the run combined. It's the only thing you need to open. `results/qc/<plate>/` alongside it holds each plate's raw CellProfiler QC output, if you need to dig into a specific image's underlying data. There's no `excluded.csv` published here, that file only exists once you click "Download exclusion list" in the gallery and save it somewhere yourself.

## If something goes wrong

**"Cannot connect to the Docker daemon."** Docker isn't running. On Windows/macOS, open Docker Desktop and wait for its icon in the system tray or menu bar to stop animating, then retry. On Linux, run `sudo systemctl start docker`.

**On Windows, `docker` commands work in PowerShell but not inside the Ubuntu/WSL terminal.** Docker Desktop's WSL integration for the Ubuntu distro isn't switched on. Open Docker Desktop, Settings, Resources, WSL Integration, and enable it there (Setup > Path B, step 3).

**"Connection refused" or the SSH connection just hangs (Path A).** Double check the cluster's head node address and that you're on the right network, some clusters are only reachable from a specific Wi-Fi or VPN. Ask whoever manages the cluster to confirm the address is still current.

**The run stops partway through with a pycytominer/normalize error.** This step needs DMSO control wells to compare against. It usually means your `platemap.csv` is missing DMSO rows for that plate, or you're running a tiny test dataset that doesn't have enough wells. Add `--profiling false` to stop after the raw per-cell measurements instead.

**A Path B run on Windows dies partway through, seemingly out of memory.** WSL2 caps itself at half your machine's RAM by default. See Setup > Path B, step 2, for raising that limit via `.wslconfig`. On macOS, the equivalent is Docker Desktop's Settings, Resources, Memory slider.

**Everything is very slow or running out of disk.** Container images alone are several GB, and results for a full plate can run into the tens of GB. Confirm you have real free space before starting a full run, especially on Path B where it competes with everything else on your machine.

**Re-running after a crash reprocesses everything from scratch.** Add `-resume` to the same `nextflow run` command (same folder, same flags) and it picks up from the last completed step instead of starting over.

## Support

Full pipeline reference, [jakobhuuse/cell-paint-pipeline](https://github.com/jakobhuuse/cell-paint-pipeline) on GitHub. Questions or something not covered here, open an issue on its [issue tracker](https://github.com/jakobhuuse/cell-paint-pipeline/issues).
