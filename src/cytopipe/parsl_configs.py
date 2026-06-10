"""Parsl configurations for CytoTable.

CytoTable parallelises its conversion work through Parsl. In this pipeline Nextflow
already fans out across plates/wells on the cluster, so each CytoTable task should stay
*inside one node* to avoid nested scheduling — use :func:`threaded` (the default).

:func:`slurm_htex` is provided for the standalone case (running CytoTable directly on a
cluster, not under Nextflow). It is intentionally not wired up by default.

Imports are done lazily so importing this module (e.g. for ``--help``) does not pull in
Parsl.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import parsl


def threaded(max_threads: int | None = None) -> parsl.Config:
    """In-node threaded config (default). Safe to run inside a Nextflow task."""
    from parsl.config import Config
    from parsl.executors.threads import ThreadPoolExecutor

    executor = ThreadPoolExecutor(label="cytopipe-threads")
    if max_threads is not None:
        executor.max_threads = max_threads
    return Config(executors=[executor])


def slurm_htex(
    *,
    partition: str,
    nodes: int = 1,
    cores_per_node: int = 16,
    walltime: str = "01:00:00",
    account: str | None = None,
) -> parsl.Config:
    """Standalone SLURM HighThroughputExecutor config.

    Only use this when running CytoTable *outside* Nextflow — otherwise Nextflow and
    Parsl would both submit jobs. TODO: tune resources for TB-scale runs.
    """
    from parsl.config import Config
    from parsl.executors import HighThroughputExecutor
    from parsl.providers import SlurmProvider

    return Config(
        executors=[
            HighThroughputExecutor(
                label="cytopipe-slurm",
                provider=SlurmProvider(
                    partition=partition,
                    account=account,
                    nodes_per_block=nodes,
                    cores_per_node=cores_per_node,
                    walltime=walltime,
                ),
            )
        ]
    )
