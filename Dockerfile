# Original credit: https://github.com/jpetazzo/dockvpn
# Original credit: https://github.com/kylemanna/docker-openvpn
#
# This fork is maintained by viach-b.
# It uses a Debian 'bookworm' base image and the official
# OpenVPN community repository to ensure the 'openvpn' binary
# is compiled with Data Channel Offload (DCO) support.

FROM debian:bookworm-slim

LABEL maintainer="viach-b"

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies for adding a new repository
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        gnupg \
        wget \
    && \
    # Add OpenVPN community repository GPG key
    wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | gpg --dearmor -o /usr/share/keyrings/openvpn-keyring.gpg \
    && \
    # Add the OpenVPN 2.6 community repository
    echo "deb [signed-by=/usr/share/keyrings/openvpn-keyring.gpg] https://build.openvpn.net/debian/openvpn/release/2.6 bookworm main" > /etc/apt/sources.list.d/openvpn-release-2.6.list \
    && \
    # Clean up wget
    apt-get remove -y wget && apt-get autoremove -y

# Install OpenVPN (from the new repo) and other dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openvpn \
        iptables \
        easy-rsa \
        qrencode \
        bash \
        iproute2 \
    && \    
    # The 'easy-rsa' package installs its binary to /usr/share/easy-rsa,
    # which is not in the $PATH. We create a symlink in /usr/local/bin
    # (which is in $PATH) so the scripts can find it.
    ln -s /usr/share/easy-rsa/easyrsa /usr/local/bin/easyrsa \
    && \
    # Clean up apt caches
    rm -rf /var/lib/apt/lists/*

# Set environment variables, mirroring kylemanna's setup
ENV OPENVPN=/etc/openvpn
ENV EASYRSA=/usr/share/easy-rsa \
    EASYRSA_CRL_DAYS=3650 \
    EASYRSA_PKI=$OPENVPN/pki

# Expose OpenVPN data volume
VOLUME ["/etc/openvpn"]

# Expose default OpenVPN port
EXPOSE 1194/udp

# Add helper scripts (bin directory)
ADD ./bin /usr/local/bin
# THIS IS THE FIX:
# We now correctly set permissions *after* adding the files.
RUN chmod a+x /usr/local/bin/*

# Default command to run OpenVPN
CMD ["ovpn_run"]