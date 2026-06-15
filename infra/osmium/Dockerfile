# Pinned osmium-tool image for the PBF-derived camera substrate (ADR 0002).
#
# build-cameras.sh filters ALPR nodes out of the local OSM extract with osmium.
# Rather than require osmium-tool on the host (a dev-machine dependency), we run
# it from this tiny self-built image — debian-slim + osmium-tool, no third-party
# image and nothing copied in. Built on demand and cached locally.
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends osmium-tool \
 && rm -rf /var/lib/apt/lists/*

ENTRYPOINT []
