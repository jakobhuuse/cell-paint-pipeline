# Running the pipeline

Back to [README](../README.md).

Nextflow needs a Unix-like environment. It runs natively on macOS and Linux. On Windows it needs WSL, which Path B below sets up for you as its first step, an optional step that only applies if you're on Windows. Path A skips your own machine entirely and runs everything on a remote SLURM cluster, that route works the same regardless of which OS you're on, since all you need locally is an SSH client.

## Pick your path

**Path A, run it on a SLURM cluster (recommended for real experiments).** You connect over the network and everything runs there. Your machine only sends files and watches progress. Best for real experiments and large datasets.

**Path B, run it on your own machine.** A one-time setup installs Docker (plus WSL2 first, if you're on Windows). Best for trying the pipeline out, small test datasets, or when you don't have cluster access. You can run real experiments this way, but it obviously won't run as fast as on a SLURM cluster.

## Words you'll run into

- **Nextflow**, the tool that drives the pipeline. You give it one command and it runs every processing step in the right order.
- **Pipeline branch**, which set of tools does the feature extraction, `deepprofiler` (a deep-learning model, the default) or `cellprofiler` (classical image measurements). Choose with `--pipeline`.
- **Container (Docker / Apptainer)**, a sealed, ready-made copy of CellProfiler, DeepProfiler, and the rest, so you never install that software yourself.

## Before you start (both paths)

Have these ready regardless of which path you take.

- Your images, `.tif` files, organized in one folder per plate.
- A `platemap.csv` sitting directly alongside those plate folders, mapping wells to compounds.
- A decision on which branch to run, `deepprofiler` (default, benefits from running on a GPU) or `cellprofiler` (CPU-only, classical measurements).

Expected layout:

```text
my_experiment/
    platemap.csv
    2026-01-15/
        26159/               # one plate's .tif images live in here
        26159/TimePoint_1/   # or, if your scope exports one folder per timepoint, one level deeper
        26160/               # each plate gets its own folder either way
```

The pipeline looks for `.tif` files anywhere inside each plate folder, so a `TimePoint_1` subfolder (or several, one per timepoint) works with no extra setup, nothing to change on the command line for that.

## Adjusting parameters

The commands below cover the flags you'll change most often, `--pipeline`, `--input_dir`, `--outdir`. Everything else keeps a sensible default, but you can override any of them by adding `--name value` to the `nextflow run` command. The full list, grouped by tool, is documented in [docs/parameters.md](parameters.md).

## Path A, run it on the SLURM cluster

Nothing is installed on your own machine beyond an SSH program, both Windows and macOS/Linux already ship one.

Before you begin, get three things from whoever manages your cluster (your PI, IT, or the person who set it up).

- The cluster's head node address, e.g. `203.0.113.42` (`<head-ip>` below).
- Your login username (usually `ubuntu`) and either a password or an SSH key file they give you.
- A name for your experiment folder, e.g. `my_experiment`.

1. **Open a terminal.** On Windows, press Start, type `PowerShell`, and open it, Windows 10/11 ships an SSH client built in. On macOS or Linux, open your normal Terminal app, it already has one too.

2. **Connect to the cluster.**

   ```bash
   ssh ubuntu@<head-ip>
   ```

   Type `yes` if asked to trust the head node the first time, then enter your password. If you were given a key file, connect with `ssh -i /path/to/key.pem ubuntu@<head-ip>` instead (`ssh -i C:\path\to\key.pem ubuntu@<head-ip>` on Windows).

3. **Create a folder for this experiment.** Still connected over SSH. Replace `<my_experiment>` with the experiment's name.

   ```bash
   mkdir -p /data/<my_experiment>/input
   ```

4. **Copy your data across.** Open a second, separate terminal window on your own machine (leave the first one connected) and run.

   ```powershell
   # Windows (PowerShell)
   scp -r C:\Users\you\Desktop\my_experiment\* ubuntu@<head-ip>:/data/<my_experiment>/input/
   ```

   ```bash
   # macOS / Linux
   scp -r ~/Desktop/my_experiment/* ubuntu@<head-ip>:/data/<my_experiment>/input/
   ```

   If typing file paths feels error-prone, a graphical alternative works just as well, [WinSCP](https://winscp.net/) on Windows, [Cyberduck](https://cyberduck.io/) on macOS. Both let you drag and drop your plate folders and `platemap.csv` onto the cluster through a two-pane window, like copying files between two folders in File Explorer or Finder.

   This can take a while for a full plate of images, let it finish before moving on.

5. **Start a session that survives disconnects.** Back in your first window (the one connected over SSH).

   ```bash
   tmux new -s my_experiment
   ```

   Everything you type after this keeps running even if your machine sleeps or loses Wi-Fi. If you get disconnected, reconnect with step 2, then run `tmux attach -t my_experiment` to get back to where you left off.

6. **Move into your experiment folder.**

   ```bash
   cd /data/my_experiment
   ```

7. **Run the pipeline on your data.**

   ```bash
   nextflow run jakobhuuse/cell-paint-pipeline -profile slurm \
       --pipeline deepprofiler \
       --input_dir input --outdir results
   ```

   Swap `--pipeline deepprofiler` for `--pipeline cellprofiler` to use the other branch. This is the command that does the real work, expect it to run for a while on a full plate.

8. **Step away safely.** Detach from the session with `Ctrl+B` then `D` (do **NOT** press `Ctrl+D`, this shuts down the session), the run keeps going. Close your terminal, disconnect Wi-Fi, whatever you need. Reconnect any time with `ssh ubuntu@<head-ip>` then `tmux attach -t my_experiment` to check on it.

9. **Collect your results.** Once Nextflow prints `Completed successfully`, results sit in `/data/my_experiment/results/` on the cluster. Pull them back the same way you sent images over, in reverse, with `scp` or a graphical tool.

   ```powershell
   # Windows (PowerShell)
   scp -r ubuntu@<head-ip>:/data/my_experiment/results C:\Users\you\Desktop\my_experiment\
   ```

   ```bash
   # macOS / Linux
   scp -r ubuntu@<head-ip>:/data/my_experiment/results ~/Desktop/my_experiment/
   ```

## Path B, run it on your own machine

A one-time setup, needs administrator rights on the machine and about 20 GB of free disk space.

A laptop can comfortably run the bundled test images or a handful of wells. A full plate, especially on the `deepprofiler` branch which wants a GPU, is realistically a job for Path A. Treat this path as "try it out," not "process my real experiment."

1. **(Windows only) Set up WSL2 first.** Nextflow needs a Unix-like environment, and Windows doesn't ship one on its own. Press Start, type `PowerShell`, right-click it and choose "Run as administrator," then run.

   ```powershell
   wsl --install
   ```

   Restart the PC when it asks. This installs both WSL2 and a bundled Ubuntu Linux system. After restarting, open "Ubuntu" from the Start menu, on first launch it asks you to pick a username and password for this Linux environment, any values are fine, just remember them. Every step below happens inside that Ubuntu terminal, not PowerShell.

   If you're on macOS or Linux, skip this step entirely, you already have a native terminal that works, open it and continue below.

2. **Install Docker.** On Windows, download and install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/), keep "Use WSL 2 based engine" checked during setup (it's the default), then open Docker Desktop, Settings, Resources, WSL Integration, and switch on integration with the Ubuntu distro. On macOS, install [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/). On Linux, install [Docker Engine](https://docs.docker.com/engine/install/) for your distribution.

3. **Install Java and Nextflow.** On Windows, open the "Ubuntu" app from the Start menu to get back into your WSL terminal (or type `wsl` into PowerShell, which drops you into the same place). Nextflow needs Java to run, and it isn't installed by anything above yet.

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

4. **Check everything works.**

   ```bash
   nextflow -version
   docker run hello-world
   ```

   The second command should print a short "Hello from Docker!" message. If it instead complains it can't connect, open Docker Desktop (Windows/macOS) or start the Docker service (`sudo systemctl start docker` on Linux) and make sure it's running.

5. **Create a folder for this experiment, no need to copy your data in.** Nextflow stages input files with symlinks rather than copies, so pointing `--input_dir` straight at wherever your images and `platemap.csv` already sit works fine, and doesn't cost you double the disk space for a dataset that's already large. Keeping this experiment folder itself on the native Linux filesystem is what actually matters for speed, it's where Nextflow's own work directory and your results will live, and that sees far more small-file activity than a one-time read of each image.

   ```bash
   mkdir -p ~/my_experiment
   ```

6. **Do a quick test run first.** Confirm the setup works end-to-end using the pipeline's small bundled sample data before trying your own.

   ```bash
   nextflow run jakobhuuse/cell-paint-pipeline -profile standard --pipeline cellprofiler --profiling false
   ```

   This pulls a few container images the first time, so expect it to take longer on the first run than later ones.

7. **Run it on your own data.**

   ```bash
   # Windows: /mnt/c/... is how Ubuntu sees your Windows C: drive, point straight at it.
   cd ~/my_experiment
   nextflow run jakobhuuse/cell-paint-pipeline -profile standard \
       --pipeline cellprofiler \
       --input_dir /mnt/c/Users/you/Desktop/my_experiment --outdir results
   ```

   ```bash
   # macOS / Linux: point straight at wherever your files already are.
   cd ~/my_experiment
   nextflow run jakobhuuse/cell-paint-pipeline -profile standard \
       --pipeline cellprofiler \
       --input_dir ~/Desktop/my_experiment --outdir results
   ```

   If you have an NVIDIA GPU, swap `-profile standard` for `-profile gpu` to speed up the `deepprofiler` branch. On Windows it needs the [NVIDIA CUDA driver for WSL](https://docs.nvidia.com/cuda/wsl-user-guide/index.html) installed first. On Linux it needs the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html). Apple Silicon and AMD Macs have no NVIDIA GPU, so this option doesn't apply there. Treat it as optional either way.

8. **Find your results.** On Windows, results land in `~/my_experiment/results/` inside Ubuntu. Browse them with Windows File Explorer by running `explorer.exe .` from inside that folder in the Ubuntu terminal, or by typing `\\wsl$\Ubuntu\home\<your-username>\my_experiment\results` into an Explorer address bar. On macOS or Linux, results already sit directly in `~/my_experiment/results/`, open it with your normal file manager or `open .` (macOS) / `xdg-open .` (Linux).

## Reading the results

Everything lands under `results/<pipeline>/`, named after whichever branch you ran, so a `deepprofiler` run and a `cellprofiler` run never overwrite each other.

| Folder                    | What's in it                                                              |
| ------------------------- | ------------------------------------------------------------------------- |
| `qc/<plate>/`             | Quality-control images per plate, check these first if a run looks wrong. |
| `raw/`                    | One row of measurements per cell, before any averaging.                   |
| `normalized/`             | The same measurements, adjusted against your DMSO control wells.          |
| `<pipeline>/` (top level) | The final table, one row per compound, plus QC report figures.            |

## If something goes wrong

**"Cannot connect to the Docker daemon."** Docker isn't running. On Windows/macOS, open Docker Desktop and wait for its icon in the system tray or menu bar to stop animating, then retry. On Linux, run `sudo systemctl start docker`.

**"Connection refused" or the SSH connection just hangs (Path A).** Double check the cluster's head node address and that you're on the right network, some clusters are only reachable from a specific Wi-Fi or VPN. Ask whoever manages the cluster to confirm the address is still current.

**The run stops partway through with a pycytominer/normalize error.** This step needs DMSO control wells to compare against. It usually means your `platemap.csv` is missing DMSO rows for that plate, or you're running a tiny test dataset that doesn't have enough wells. Add `--profiling false` to stop after the raw per-cell measurements instead.

**Everything is very slow or running out of disk.** Container images alone are several GB, and results for a full plate can run into the tens of GB. Confirm you have real free space before starting a full run, especially on Path B where it competes with everything else on your machine.

**Re-running after a crash reprocesses everything from scratch.** Add `-resume` to the same `nextflow run` command (same folder, same flags) and it picks up from the last completed step instead of starting over.

## Support

Full pipeline reference, [jakobhuuse/cell-paint-pipeline](https://github.com/jakobhuuse/cell-paint-pipeline) on GitHub. Questions or something not covered here, open an issue on its [issue tracker](https://github.com/jakobhuuse/cell-paint-pipeline/issues).
