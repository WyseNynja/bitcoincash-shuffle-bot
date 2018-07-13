FROM python:3.6-alpine3.7

VOLUME /home/abc/.electron-cash /var/lib/tor

# this isn't going to change, so keep it first
ENTRYPOINT ["/init"]
CMD []

# bash for entrypoint script
# coreutils for chroot
# curl for downloads
# pip was unhappy installing with qt5 so install it to the system
# Tor for privacy
RUN apk add --no-cache \
    bash \
    ca-certificates \
    coreutils \
    curl \
    gnupg \
    py3-qt5 \
    tor \
    torsocks \
;

# https://github.com/just-containers/s6-overlay/releases
ENV S6_GPGKEY=DB301BA3F6F807E0D0E6CCB86101B2783B2FD161
ENV S6_VERSION=1.21.4.0
RUN { set -eux; \
    \
    cd /tmp; \
    curl -L -o /tmp/s6-overlay-amd64.tar.gz https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-amd64.tar.gz; \
    curl -L -o /tmp/s6-overlay-amd64.tar.gz.sig https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-amd64.tar.gz.sig; \
    export GNUPGHOME="$(mktemp -d -p /tmp)"; \
    curl https://keybase.io/justcontainers/key.asc | gpg --import; \
    gpg --list-keys "$S6_GPGKEY"; \
    gpg --batch --verify s6-overlay-amd64.tar.gz.sig s6-overlay-amd64.tar.gz; \
    tar xzf /tmp/s6-overlay-amd64.tar.gz -C /; \
    rm -rf /tmp/*; \
}

# create a user so that we can avoid running as root
RUN { set -eux; \
    \
    addgroup -g 911 abc; \
    adduser -G abc -D -u 911 abc; \
}
ENV HOME /home/abc

# create a virtualenv so we can avoid pip installing to the system install
ENV PATH /pyenv/bin:$PATH
RUN { set -eux; \
    \
    mkdir /pyenv; \
    chown abc:abc /pyenv; \
    chroot --userspec=abc / python3.6 -m venv /pyenv --system-site-packages; \
}

# download electrum
ENV ELECTRUM_VERSION=3.3
ENV ELECTRUM_SHA256SUM=92df7f89321cda8f6d886c203298daa1bf8463ff25a5d58b93907579d181f7f8
RUN { set -eux; \
    \
    mkdir /opt; \
    cd /opt; \
    curl -fSL -o electrum.tgz https://github.com/fyookball/electrum/archive/${ELECTRUM_VERSION}.tar.gz; \
    echo "$ELECTRUM_SHA256SUM  electrum.tgz" | sha256sum -c -; \
    tar -zxvf electrum.tgz; \
    rm electrum.tgz; \
    ln -sfv "electrum-${ELECTRUM_VERSION}" electrum; \
}

# download cashshuffle electron cash plugin
ENV SHUFFLE_PLUGIN_VERSION=0.4.0
ENV SHUFFLE_PLUGIN_SHA256SUM=63a2ecfcbb4f8b9a10e460cd54f76f8d2ba5c536d935707dd39da8a1cdf6f094
RUN { set -eux; \
    \
    cd /opt; \
    curl -fSL -o shuffle-plugin.tgz https://github.com/cashshuffle/cashshuffle-electron-cash-plugin/archive/v${SHUFFLE_PLUGIN_VERSION}.tar.gz; \
    echo "$SHUFFLE_PLUGIN_SHA256SUM  shuffle-plugin.tgz" | sha256sum -c -; \
    tar -zxvf shuffle-plugin.tgz; \
    rm shuffle-plugin.tgz; \
    cd electrum/plugins; \
    ln -sfv "../../cashshuffle-electron-cash-plugin-${SHUFFLE_PLUGIN_VERSION}/shuffle"; \
}

# we need pip.conf before pip installing
COPY pip.conf /etc/

# Tor monitor
RUN chroot --userspec=abc / pip install nyx

# install electron cash
COPY electrum.patch /opt/electrum/
RUN { set -eux; \
    \
    cd /opt/electrum; \
    patch -p1 < ./electrum.patch; \
    \
    mkdir build dist Electron_Cash.egg-info; \
    chown abc:abc build dist Electron_Cash.egg-info; \
    \
    chroot --userspec=abc / pip install schedule; \
    chroot --userspec=abc --skip-chdir / python3 setup.py install; \
}

# copy configuration to the image
COPY rootfs/ /