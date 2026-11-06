# mql-compiler: compile MQL4 and MQL5 sources with MetaQuotes' own MetaEditor,
# running under Wine on Linux. No Windows, no terminal, no account.
#
# The image carries Wine and the compile script only. The MT4 and MT5
# installers are MetaQuotes software and are not redistributed: the first run
# downloads them from RoboForex, checks the MetaQuotes code signature, and
# installs them into /cache, which a volume keeps between runs.
FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

LABEL org.opencontainers.image.title="mql-compiler" \
      org.opencontainers.image.description="Compile MQL4 and MQL5 with MetaEditor under Wine" \
      org.opencontainers.image.source="https://github.com/psyb0t/docker-mql-compiler" \
      org.opencontainers.image.licenses="WTFPL"

# Wine comes from WineHQ, not Debian. MetaTrader 5 build 6304 refuses to run
# under Debian's Wine 10.0: the terminal stops at "A debugger has been found
# running in your system" and MetaEditor's /compile exits with no log. Wine
# 11.0 runs both. The packages are pinned to one version, and WineHQ's signing
# key to its checksum (fingerprint D43F 6401 4536 9C51 D786 DDEA 76F1 A20F
# F987 672F).
ARG WINE_VERSION=11.0.0.0~trixie-1
ARG WINEHQ_SIGNER_SHA256=d965d646defe94b3dfba6d5b4406900ac6c81065428bf9d9303ad7a72ee8d1b8

# The checksum check below pipes into sha256sum; a failed download must fail
# the build, not just the last command of the pipe.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# MT4's MetaEditor is a 32-bit program, so Wine needs its i386 half too.
# xvfb gives the installers and the terminals a display they never show.
# osslsigncode checks the installers' Authenticode signature before they run;
# jq writes the JSON results and log lines; inotify-tools drives --watch.
# hadolint ignore=DL3008
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        inotify-tools \
        jq \
        osslsigncode \
        procps \
        xauth \
        xvfb \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL -o /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
    && echo "$WINEHQ_SIGNER_SHA256  /etc/apt/keyrings/winehq-archive.key" | sha256sum -c - \
    && printf '%s\n' \
        'Types: deb' \
        'URIs: https://dl.winehq.org/wine-builds/debian' \
        'Suites: trixie' \
        'Components: main' \
        'Architectures: amd64 i386' \
        'Signed-By: /etc/apt/keyrings/winehq-archive.key' \
        >/etc/apt/sources.list.d/winehq-trixie.sources \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        "winehq-stable=$WINE_VERSION" \
        "wine-stable=$WINE_VERSION" \
        "wine-stable-amd64=$WINE_VERSION" \
        "wine-stable-i386:i386=$WINE_VERSION" \
    && rm -rf /var/lib/apt/lists/*

# Runs as any UID: the wrapper passes the caller's own so compiled files belong
# to them. /cache is the only writable state; each UID keeps its toolchain in
# /cache/uid-<UID>, so one volume serves every user. Sticky and world-writable
# (like /tmp) so a fresh volume lets any UID create its own folder and none
# can touch another's.
RUN useradd --uid 1000 --create-home --shell /usr/sbin/nologin mql \
    && install -d -m 1777 /cache \
    && install -d -o mql -g mql -m 0755 /src

ENV WINEDEBUG=-all \
    WINEDLLOVERRIDES="mscoree,mshtml=" \
    DISPLAY=:99

COPY --chown=root:root --chmod=0755 entrypoint.sh /usr/local/bin/mql-compiler
# --version reports this.
COPY --chown=root:root --chmod=0644 VERSION /usr/local/share/mql-compiler-version

USER 1000:1000
WORKDIR /src
VOLUME ["/cache"]
ENTRYPOINT ["/usr/local/bin/mql-compiler"]
