# syntax=docker/dockerfile:1
FROM buildpack-deps:buster as builder

WORKDIR /nsjail

RUN apt-get -y update \
    && apt-get install -y --no-install-recommends \
        bison\
        flex \
        libprotobuf-dev\
        libnl-route-3-dev \
        protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

RUN git clone -b master --single-branch https://github.com/google/nsjail.git . \
    && git checkout dccf911fd2659e7b08ce9507c25b2b38ec2c5800
RUN make

# ------------------------------------------------------------------------------
FROM python:3.11-slim-buster as base

# Everything will be a user install to allow snekbox's dependencies to be kept
# separate from the packages exposed during eval.
ENV PATH=/root/.local/bin:$PATH \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=false \
    PIP_USER=1

RUN apt-get -y update \
    && apt-get install -y --no-install-recommends \
        gcc \
        git \
        libnl-route-3-200 \
        libprotobuf17 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /nsjail/nsjail /usr/sbin/
RUN chmod +x /usr/sbin/nsjail

# ------------------------------------------------------------------------------
FROM base as venv

COPY requirements/ /snekbox/requirements/
WORKDIR /snekbox

# pip installs to the default user site since PIP_USER is set.
RUN pip install -U -r requirements/requirements.pip

# This must come after the first pip command! From the docs:
# All RUN instructions following an ARG instruction use the ARG variable
# implicitly (as an environment variable), thus can cause a cache miss.
ARG DEV

# Install numpy when in dev mode; one of the unit tests needs it.
RUN if [ -n "${DEV}" ]; \
    then \
        pip install -U -r requirements/coverage.pip \
        && PYTHONUSERBASE=/snekbox/user_base pip install numpy~=1.19; \
    fi

# At the end to avoid re-installing dependencies when only a config changes.
COPY config/ /snekbox/config/

ENTRYPOINT ["gunicorn"]
CMD ["-c", "config/gunicorn.conf.py"]

# ------------------------------------------------------------------------------
FROM venv

# Use a separate directory to avoid importing the source over the installed pkg.
# The venv already installed dependencies, so nothing besides snekbox itself
# will be installed. Note requirements.pip cannot be used as a constraint file
# because it contains extras, which pip disallows.
RUN --mount=source=.,target=/snekbox_src,rw \
    pip install /snekbox_src[gunicorn,sentry]
