# DeepProfiler image — built from GitHub.
#
# DeepProfiler has no published Docker image and no working PyPI release, so we install
# from source. It uses TensorFlow and benefits from a GPU at the `profile` step.

FROM tensorflow/tensorflow:2.15.0

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
        "git+https://github.com/cytomining/DeepProfiler.git"

# DeepProfiler is invoked as a module/CLI by Nextflow with explicit --root/--config/etc.
ENTRYPOINT ["python", "-m", "deepprofiler"]
