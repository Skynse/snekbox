# Use official Python base image directly
FROM python:3.12-slim-bookworm as base

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=false

RUN apt-get -y update \
    && apt-get install -y --no-install-recommends \
        gcc \
        git \
        libnl-route-3-200 \
        libprotobuf32 \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
FROM buildpack-deps:bookworm as builder-nsjail

WORKDIR /nsjail

RUN apt-get -y update \
    && apt-get install -y --no-install-recommends \
        bison \
        flex \
        libprotobuf-dev \
        libnl-route-3-dev \
        protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

RUN git clone -b master --single-branch https://github.com/google/nsjail.git . \
    && git checkout dccf911fd2659e7b08ce9507c25b2b38ec2c5800
RUN make

# Copy nsjail binary
COPY --link --from=builder-nsjail /nsjail/nsjail /usr/sbin/

RUN chmod +x /usr/sbin/nsjail

# ------------------------------------------------------------------------------
FROM base as venv

COPY --link requirements/ /snekbox/requirements/
COPY --link scripts/install_eval_deps.sh /snekbox/scripts/install_eval_deps.sh
WORKDIR /snekbox

RUN pip install -U -r requirements/requirements.pip

# This must come after the first pip command!
ARG DEV

# Install numpy when in dev mode; one of the unit tests needs it.
RUN if [ -n "${DEV}" ]; \
    then \
        pip install -U -r requirements/coverage.pip \
        && export PYTHONUSERBASE=/snekbox/user_base \
        && python -m pip install --user numpy~=1.19; \
    fi

# At the end to avoid re-installing dependencies when only a config changes.
COPY --link config/ /snekbox/config/

ENTRYPOINT ["gunicorn"]
CMD ["-c", "config/gunicorn.conf.py"]

# ------------------------------------------------------------------------------
FROM venv

# Use a separate directory to avoid importing the source over the installed pkg.
# The venv already installed dependencies, so nothing besides snekbox itself
# will be installed.
RUN --mount=source=.,target=/snekbox_src,rw \
    pip install /snekbox_src --config-settings="--extras=gunicorn,sentry"
