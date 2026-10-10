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

# MT4's MetaEditor is a 32-bit program, so Wine needs its i386 half too.
# xvfb gives the installers and MetaEditor a display they never show.
# osslsigncode checks the installers' Authenticode signature before they run;
# jq writes the JSON log lines.
# hadolint ignore=DL3008
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        osslsigncode \
        procps \
        wine \
        wine32:i386 \
        wine64 \
        xauth \
        xvfb \
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

COPY --chmod=0755 entrypoint.sh /usr/local/bin/mql-compiler

USER 1000:1000
WORKDIR /src
VOLUME ["/cache"]
ENTRYPOINT ["/usr/local/bin/mql-compiler"]
