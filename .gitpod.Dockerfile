FROM buildpack-deps:bionic

### base ###
ARG DEBIAN_FRONTEND=noninteractive

RUN yes | unminimize 

# Set a runlevel to avoid invoke-rc.d warnings
# http://manpages.ubuntu.com/manpages/focal/man8/runlevel.8.html#environment
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
    && echo "deb https://apt.llvm.org/focal/ llvm-toolchain-focal main" >> /etc/apt/sources.list.d/llvm.list \
    && sudo apt install -yq --no-install-recommends \
        clang \
        clang-format \
        clang-tidy \
        gdb \
        lld

### Docker ###
LABEL dazzle/layer=tool-docker
LABEL dazzle/test=tests/tool-docker.yaml
USER root
ENV TRIGGER_REBUILD=3
# https://docs.docker.com/engine/install/ubuntu/
RUN curl -o /var/lib/apt/dazzle-marks/docker.gpg -fsSL https://download.docker.com/linux/ubuntu/gpg \
    && apt-key add /var/lib/apt/dazzle-marks/docker.gpg \
    && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    && sudo apt install -yq --no-install-recommends docker-ce docker-ce-cli containerd.io

RUN curl -o /usr/bin/slirp4netns -fsSL https://github.com/rootless-containers/slirp4netns/releases/download/v1.1.12/slirp4netns-$(uname -m) \
    && chmod +x /usr/bin/slirp4netns

RUN curl -o /usr/local/bin/docker-compose -fsSL https://github.com/docker/compose/releases/download/1.29.2/docker-compose-Linux-x86_64 \
    && chmod +x /usr/local/bin/docker-compose

# https://github.com/wagoodman/dive
RUN curl -o /tmp/dive.deb -fsSL https://github.com/wagoodman/dive/releases/download/v0.10.0/dive_0.10.0_linux_amd64.deb \
    && apt install /tmp/dive.deb \
    && rm /tmp/dive.deb

### Install Tailscale ###
LABEL dazzle/layer=tool-tailscale
LABEL dazzle/test=tests/tool-tailscale.yaml
USER root
# Dazzle does not rebuild a layer until one of its lines are changed. Increase this counter to rebuild this layer.
ENV TRIGGER_REBUILD=1

RUN curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.gpg | sudo apt-key add - \
    && curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.list | sudo tee /etc/apt/sources.list.d/tailscale.list \
    && apt-get update \
    && apt-get install -y tailscale

### Install nix ###
LABEL dazzle/layer=tool-nix
LABEL dazzle/test=tests/tool-nix.yaml
ENV NIX_VERSION=2.3.14
# Dazzle does not rebuild a layer until one of its lines are changed. Increase this counter to rebuild this layer.
ENV TRIGGER_REBUILD=1

USER root
RUN addgroup --system nixbld \
  && adduser gitpod nixbld \
  && for i in $(seq 1 30); do useradd -ms /bin/bash nixbld$i && adduser nixbld$i nixbld; done \
  && mkdir -m 0755 /nix && chown gitpod /nix \
  && mkdir -p /etc/nix && echo 'sandbox = false' > /etc/nix/nix.conf

# Install Nix
USER gitpod
ENV USER gitpod
WORKDIR /home/gitpod

RUN curl https://nixos.org/releases/nix/nix-$NIX_VERSION/install | sh

RUN echo '. /home/gitpod/.nix-profile/etc/profile.d/nix.sh' >> /home/gitpod/.bashrc
RUN mkdir -p /home/gitpod/.config/nixpkgs && echo '{ allowUnfree = true; }' >> /home/gitpod/.config/nixpkgs/config.nix

# Install cachix
RUN . /home/gitpod/.nix-profile/etc/profile.d/nix.sh \
  && nix-env -iA cachix -f https://cachix.org/api/v1/install \
  && cachix use cachix

# share env see https://github.com/gitpod-io/workspace-images/issues/472
RUN echo "PATH="${PATH}"" | sudo tee /etc/environment

USER root
ENV MAKEFLAGS="-j$(nproc)"

# Import the Kurento repository signing key
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 5AFA7A83

# Get Ubuntu version definitions
ENV DISTRIB_CODENAME=bionic

# Add the repository to Apt
RUN echo "deb [arch=amd64] http://ubuntu.openvidu.io/dev $DISTRIB_CODENAME kms6" >> /etc/apt/sources.list.d/kurento.list

RUN apt-get update \
    && apt-get install -yq --no-install-recommends \
        libssl1.0-dev \
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