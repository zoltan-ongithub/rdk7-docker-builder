FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8

RUN apt-get update && apt-get install -y \
    build-essential chrpath cmake curl diffstat g++ g++-multilib gcc gcc-multilib \
    git git-flow git-man jq llvm make python3.8 python3.8-dev python3.8-venv python3-pip \
    ripgrep sysstat texinfo tk-dev tree wget xz-utils zip zstd \
    libbz2-dev libffi-dev libglib2.0-dev libldap2-dev liblzma-dev libncurses5-dev \
    libreadline-dev libsasl2-dev libsqlite3-dev libslang2-dev libssl-dev libxml2-dev \
    libxmlsec1-dev zlib1g-dev ant nnn locales \
    cpio gawk lz4 \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USERNAME=rdk

RUN groupadd -g $GROUP_ID $USERNAME && \
    useradd -m -u $USER_ID -g $GROUP_ID -s /bin/bash $USERNAME && \
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p /opt/bin && \
    curl -o /opt/bin/repo https://storage.googleapis.com/git-repo-downloads/repo && \
    chmod a+x /opt/bin/repo

RUN mkdir -p /workspace && chown $USERNAME:$USERNAME /workspace

RUN python3.8 -m pip install --upgrade pip setuptools wheel
RUN python3.8 -m pip install pyyaml requests jinja2 markupsafe

COPY setup.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
USER $USERNAME
ENV PATH="/opt/bin:$PATH"

RUN git config --global init.defaultBranch main

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
