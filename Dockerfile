# hermes-docker-testbed layer: atm + herdr + tmux + hermes-atm + stub agents
# Built FROM the fork's own production image (loki/hermes-testbed:base).
# amd64 under Rosetta (colima VM is arm64; atm release is x86_64-only — see issue #1057).
FROM loki/hermes-testbed:base

USER root

# tmux: the rmux-parity agent surface (herdr is the primary surface)
# openssh-server: cross-host peer mode (AR item 7) — the smoke harness drives
# the remote side over `ssh <peer> atm ...`. Hardening: key-only auth
# (PasswordAuthentication no), no passwords, throwaway build-time keypair.
# Root login is key-only (prohibit-password) because the container's ATM state
# and daemon live under /root — ssh as root is required to address the same
# daemon context; documented wall exception in README.
RUN apt-get -o Acquire::Retries=3 update && \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends tmux openssh-server && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/sshd /root/.ssh && \
    ssh-keygen -A && \
    ssh-keygen -t ed25519 -N '' -f /root/.ssh/testbed_peer_key -C 'testbed-throwaway-peer-key' && \
    cat /root/.ssh/testbed_peer_key.pub >> /root/.ssh/authorized_keys && \
    chmod 600 /root/.ssh/authorized_keys && \
    printf 'Port 22\nPermitRootLogin prohibit-password\nPasswordAuthentication no\nChallengeResponseAuthentication no\nUsePAM no\n' > /etc/ssh/sshd_config.d/testbed.conf

# herdr 0.8.2 — native Rust, musl static, sha256 verified against v0.8.2 release
COPY --chmod=0755 assets/herdr-linux-x86_64 /usr/local/bin/herdr

# atm + atm-daemon from the GitHub Release tarball (the installer path).
# Filenames parametrized so pre-release drops (ATM_TARBALL env override in
# build.sh) install through the identical COPY/install path.
ARG ATM_TARBALL=atm_1.4.3_x86_64-unknown-linux-gnu.tar.gz
COPY assets/${ATM_TARBALL} /tmp/atm.tar.gz
# Layout-tolerant install: 1.4.3+ prerelease archives nest under a top-level
# dir (atm_<ver>_<triple>/bin/...); older releases are flat (bin/...). Find
# the binaries wherever they land.
RUN mkdir -p /tmp/atm-dist && tar -xzf /tmp/atm.tar.gz -C /tmp/atm-dist && \
    ATM_BIN="$(find /tmp/atm-dist -type f -path '*/bin/atm' | head -1)" && \
    ATMD_BIN="$(find /tmp/atm-dist -type f -path '*/bin/atm-daemon' | head -1)" && \
    install -m 0755 "$ATM_BIN" /usr/local/bin/atm && \
    install -m 0755 "$ATMD_BIN" /usr/local/bin/atm-daemon && \
    rm -rf /tmp/atm.tar.gz /tmp/atm-dist

# hermes-atm (injection seam client) into the hermes venv.
# Both wheels installed hermetically — no index resolution (the base image
# pins exclude-newer, which filters atm-graft out of TestPyPI).
ARG HERMES_ATM_WHEEL=hermes_atm-1.4.2-py3-none-any.whl
ARG ATM_GRAFT_WHEEL=atm_graft-1.4.3-cp311-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
COPY assets/${HERMES_ATM_WHEEL} assets/${ATM_GRAFT_WHEEL} /tmp/
RUN uv pip install --python /opt/hermes/.venv/bin/python --no-index \
      /tmp/${HERMES_ATM_WHEEL} \
      /tmp/${ATM_GRAFT_WHEEL} && \
    rm /tmp/${HERMES_ATM_WHEEL} /tmp/${ATM_GRAFT_WHEEL} && \
    /opt/hermes/.venv/bin/python -c "import hermes_atm, atm_graft, importlib.metadata as m; print('hermes_atm', m.version('hermes-atm'), '| atm_graft', m.version('atm-graft'), '| seam client module:', hermes_atm.__name__)"

# Test-team config + stub agents (graph test actors)
COPY testbed/atm.toml /opt/testbed/.atm.toml
COPY --chmod=0755 testbed/stub-agent.sh /opt/testbed/stub-agent.sh
COPY --chmod=0755 testbed/test-smoke.sh /opt/testbed/test-smoke.sh
COPY testbed/test-seam.py /opt/testbed/test-seam.py
COPY testbed/seam_harness.py /opt/testbed/seam_harness.py
COPY testbed/result.py /opt/testbed/result.py
COPY testbed/test-tier-a.py /opt/testbed/test-tier-a.py
COPY testbed/test-tier-b.py /opt/testbed/test-tier-b.py
COPY testbed/test-tier-c.py /opt/testbed/test-tier-c.py
COPY testbed/test-tier-d.py /opt/testbed/test-tier-d.py
COPY --chmod=0755 testbed/test-graph.sh /opt/testbed/test-graph.sh
COPY assets/asset-provenance.txt /opt/testbed/asset-provenance.txt
COPY prompts /opt/testbed/prompts
COPY --chmod=0755 testbed/harness/run-prompts.sh /opt/testbed/harness/run-prompts.sh
COPY --chmod=0755 testbed/harness/restart-daemon.sh /opt/testbed/harness/restart-daemon.sh
COPY --chmod=0755 testbed/harness/freeze-daemon.sh /opt/testbed/harness/freeze-daemon.sh
COPY --chmod=0755 testbed/harness/install-claude-code.sh /opt/testbed/harness/install-claude-code.sh
COPY --chmod=0755 testbed/harness/setup-mtls.sh /opt/testbed/harness/setup-mtls.sh

# Testbed runtime lives entirely inside the container:
#  - hermes state under /opt/data (never host-mounted)
#  - atm state under /root/.atm (isolated daemon + socket)
ENV ATM_TESTBED=1
WORKDIR /opt/testbed

CMD ["/opt/testbed/test-smoke.sh"]
