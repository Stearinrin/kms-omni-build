FROM buildpack-deps:xenial

### base ###
ARG DEBIAN_FRONTEND=noninteractive

# Set a runlevel to avoid invoke-rc.d warnings
# http://manpages.ubuntu.com/manpages/xenial/man8/runlevel.8.html#environment
# shellcheck disable=SC2034
ARG RUNLEVEL=1

# shellcheck disable=SC2034
ARG DEBIAN_FRONTEND=noninteractive
ARG DAZZLE_MARKS="/var/lib/apt/dazzle-marks/"
ARG TIMESTAMP=$(date +%s)

RUN if [ ! -d "${DAZZLE_MARKS}" ]; then \
        mkdir -p "${DAZZLE_MARKS}"; \
    fi

RUN apt-get update
RUN apt-get install -yq --no-install-recommends \
        zip \
        unzip \
        bash-completion \
        build-essential \
        ninja-build \
        htop \
        cmake \
        ca-certificates \
        gnupg \
        jq \
        less \
        locales \
        man-db \
        nano \
        software-properties-common \
        sudo \
        time \
        emacs-nox \
        vim \
        multitail \
        lsof \
        ssl-cert \
        fish \
        zsh \
    && locale-gen en_US.UTF-8

RUN cp /var/lib/dpkg/status "${DAZZLE_MARKS}/${TIMESTAMP}.status"
RUN apt-get clean -y

ENV LANG=en_US.UTF-8

### Git ###
RUN add-apt-repository -y ppa:git-core/ppa \
    && curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash \
    && apt-get install -yq --no-install-recommends git git-lfs

### Gitpod user ###
# '-l': see https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#user
RUN useradd -l -u 33333 -G sudo -md /home/gitpod -s /bin/bash -p gitpod gitpod \
    # passwordless sudo for users in the 'sudo' group
    && sed -i.bkp -e 's/%sudo\s\+ALL=(ALL\(:ALL\)\?)\s\+ALL/%sudo ALL=NOPASSWD:ALL/g' /etc/sudoers
ENV HOME=/home/gitpod
WORKDIR $HOME
# custom Bash prompt
RUN { echo && echo "PS1='\[\033[01;32m\]\u\[\033[00m\] \[\033[01;34m\]\w\[\033[00m\]\$(__git_ps1 \" (%s)\") $ '" ; } >> .bashrc

### Gitpod user (2) ###
USER gitpod
# use sudo so that user does not get sudo usage info on (the first) login
RUN sudo echo "Running 'sudo' for Gitpod: success" && \
    # create .bashrc.d folder and source it in the bashrc
    mkdir -p /home/gitpod/.bashrc.d && \
    (echo; echo "for i in \$(ls -A \$HOME/.bashrc.d/); do source \$HOME/.bashrc.d/\$i; done"; echo) >> /home/gitpod/.bashrc

# configure git-lfs
RUN sudo git lfs install --system

RUN echo "ws full starts"

### Install C/C++ compiler and associated tools ###
LABEL dazzle/layer=lang-c
LABEL dazzle/test=tests/lang-c.yaml
USER root
# Dazzle does not rebuild a layer until one of its lines are changed. Increase this counter to rebuild this layer.
ENV TRIGGER_REBUILD=3
RUN curl -o /var/lib/apt/dazzle-marks/llvm.gpg -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key \
    && apt-key add /var/lib/apt/dazzle-marks/llvm.gpg \
    && echo "deb https://apt.llvm.org/xenial/ llvm-toolchain-xenial main" >> /etc/apt/sources.list.d/llvm.list \
    && sudo apt update \
    && sudo apt install -yq --no-install-recommends \
        clang \
        clang-format \
        clang-tidy \
        gdb \
        lld

# https://github.com/wagoodman/dive
RUN curl -o /tmp/dive.deb -fsSL https://github.com/wagoodman/dive/releases/download/v0.10.0/dive_0.10.0_linux_amd64.deb \
    && apt install /tmp/dive.deb \
    && rm /tmp/dive.deb

# share env see https://github.com/gitpod-io/workspace-images/issues/472
RUN echo "PATH="${PATH}"" | sudo tee /etc/environment

USER root

# Import the Kurento repository signing key
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 5AFA7A83

# Get Ubuntu version definitions
ENV DISTRIB_CODENAME=xenial

# Add the repository to Apt
RUN echo "deb [arch=amd64] http://ubuntu.openvidu.io/dev $DISTRIB_CODENAME kms6" >> /etc/apt/sources.list.d/kurento.list

RUN apt-get update \
    && apt-get install -yq --no-install-recommends \
        kms-elements-dev \
        kms-filters-dev \
        kurento-media-server-dev

# Import the Ubuntu debug repository signing key
RUN apt-key adv --keyserver keyserver.ubuntu.com \
    --recv-keys F2EDC64DC5AEE1F6B9C621F0C8CAB6595FDFF622

# Add the repository to Apt
RUN echo "deb http://ddebs.ubuntu.com ${DISTRIB_CODENAME} main restricted universe multiverse \n\
deb http://ddebs.ubuntu.com ${DISTRIB_CODENAME}-updates main restricted universe multiverse" >> /etc/apt/sources.list.d/ddebs.list

RUN apt-get update \
    && apt-get install -yq --no-install-recommends kurento-dbg

USER gitpod
WORKDIR /workspace/kms-omni-build

ENV MAKEFLAGS="-j$(nproc)"