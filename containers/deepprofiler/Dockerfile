FROM python:3.11-slim

# System libraries required by OpenCV / image-processing dependencies.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 \
        libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Install DeepProfiler from PyPI plus a CUDA-enabled TensorFlow within the
# version range it pins.
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir \
        "deepprofiler==0.5.1" \
        "tensorflow[and-cuda]==2.15.1" \
        "pandas>=2.0,<3.0"

# tensorflow[and-cuda] installs the CUDA/cuDNN runtime as nvidia-*-cu12 pip
# wheels but does not put their lib dirs on the dynamic linker path, so
# TensorFlow cannot dlopen them and silently falls back to CPU. Register the
# wheel lib dirs with ldconfig.
RUN python3 -c "import os, glob, nvidia; b = os.path.dirname(nvidia.__file__); \
        print('\n'.join(sorted(glob.glob(os.path.join(b, '*', 'lib')))))" \
        > /etc/ld.so.conf.d/nvidia-wheels.conf \
    && ldconfig

ENTRYPOINT ["deepprofiler"]
CMD ["--help"]
