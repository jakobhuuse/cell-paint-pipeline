# DeepProfiler image — built from a pinned GitHub SHA.
#
# DeepProfiler has no published Docker image and no working PyPI release, so we install
# from source. It uses TensorFlow and benefits from a GPU at the `profile` step.
#
# STUB: pin DEEPPROFILER_SHA, confirm the CUDA/TF base tag matches the cluster's drivers,
# and add any extra system libs DeepProfiler needs.

# GPU base. Match the CUDA version to the target HPC nodes' driver.
FROM tensorflow/tensorflow:2.13.0-gpu

ARG DEEPPROFILER_SHA=REPLACE_WITH_PINNED_SHA

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
        "git+https://github.com/cytomining/DeepProfiler.git@${DEEPPROFILER_SHA}"

# DeepProfiler is invoked as a module/CLI by Nextflow with explicit --root/--config/etc.
ENTRYPOINT ["python", "-m", "deepprofiler"]
