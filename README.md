# OpenVPN with DCO (Docker)

This project is a fork of `kylemanna/docker-openvpn`, modified to run on a **Debian** base. Its primary purpose is to provide support for OpenVPN **Data Channel Offload (DCO)** for significant performance improvements.

This guide covers how to set up the host system and run the server.

## 1\. Host System Setup (DCO)

To use DCO, the host machine's kernel must have the `ovpn_dco_v2` module loaded. On most common distributions (like Ubuntu 22.04), this module is **not** included by default, even with HWE kernels.

The correct way to install it is by using the official OpenVPN repository to install the DKMS (Dynamic Kernel Module Support) package.

```bash
# 1. Add OpenVPN GPG key
sudo apt update
sudo apt install apt-transport-https gnupg lsb-release wget
wget -O - https://packages.openvpn.net/packages-repo.gpg | sudo gpg --dearmor | sudo tee /usr/share/keyrings/openvpn.gpg > /dev/null

# 2. Add the OpenVPN 3 repository (which contains the DKMS package)
echo "deb [signed-by=/usr/share/keyrings/openvpn.gpg] https://packages.openvpn.net/openvpn3/debian $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/openvpn3.list

# 3. Install the DCO DKMS module
sudo apt update
sudo apt install openvpn-dco-dkms
```

-----

### How to Verify Host Setup

After installation, the module should be available.

1.  **Load the module** (it should load automatically on boot, but this confirms it works):

    ```bash
    sudo modprobe ovpn_dco_v2
    ```

2.  **Check if it's loaded** in the kernel:

    ```bash
    lsmod | grep dco
    ```

      * **Expected Output:** You should see `ovpn_dco_v2`.

3.  **Check the kernel log** (`dmesg`) for the module's initialization message:

    ```bash
    dmesg | grep -i dco
    ```

      * **Expected Output:** You should see a line like: `OpenVPN data channel offload (ovpn-dco) ...`

If these commands succeed, your host is ready for DCO.

## 2\. Running the Server

Once the host is prepared, you must build the image and then run the container.

### One-Time Setup

First, you must generate the configuration and PKI. This image's `ovpn_genconfig` script has been modified to **automatically** create a DCO-compatible config (`topology subnet` and `allow-compression no`).

```bash
# 1. Build your custom image
docker build -t viach-b/openvpn-dco .

# 2. Create a persistent volume for config and keys
docker volume create openvpn-data

# 3. Generate the DCO-compatible configuration
# (Note: Do NOT add any extra DCO flags; the script handles it)
docker run -v openvpn-data:/etc/openvpn --rm viach-b/openvpn-dco \
    ovpn_genconfig -u udp://vpn.yourdomain.com

# 4. Initialize the Public Key Infrastructure (PKI)
# You will be asked to create and confirm a CA password.
docker run -v openvpn-data:/etc/openvpn --rm -it viach-b/openvpn-dco \
    ovpn_initpki
```
**Note** on the interactive ovpn_initpki step:

This command is interactive and requires your input to create the Certificate Authority (CA). You will be prompted for the following:

Enter New CA Key Passphrase: This is the most important step. Invent a strong password for your CA and press Enter.

Re-Enter / Verifying: You will be asked to re-type this password immediately to confirm it.

Common Name...: You will be asked for a Common Name. Simply press Enter to accept the default (Easy-RSA CA).

Confirm request details: The script will show you the server certificate details. You must type yes and press Enter to approve it.

Enter pass phrase for...: You will be asked for your CA password two more times (to sign the server certificate and again to generate the CRL).

Once all prompts are complete, the PKI will be successfully initialized.

### Start the Server

This command runs the server in detached (`-d`) mode.

```bash
docker run -d \
    -v openvpn-data:/etc/openvpn \
    -p 1194:1194/udp \
    --name openvpn-dco-server \
    --cap-add=NET_ADMIN \
    --sysctl net.ipv6.conf.all.disable_ipv6=0 \
    --sysctl net.ipv6.conf.default.forwarding=1 \
    --sysctl net.ipv6.conf.all.forwarding=1 \
    viach-b/openvpn-dco
```

**Note:** The `--cap-add=NET_ADMIN` flag is **mandatory**. It gives the container permission to interact with the kernel's DCO module.

-----

### How to Verify the Server is Running with DCO

There are two checks to perform:

1.  **Check that the container is running:**

    ```bash
    docker ps
    ```

      * **Expected Output:** You should see `openvpn-dco-server` with a status of `Up ...`.

2.  **Check the logs for the DCO confirmation messages:**

    ```bash
    docker logs openvpn-dco-server
    ```

      * **Expected Output:** Look for these specific lines, which confirm DCO is active. You should *not* see any warnings about compression or topology.

    <!-- end list -->

    ```text
    ...
    2025-11-11 10:24:48 OpenVPN 2.6.15 x86_64-pc-linux-gnu ... [DCO]
    ...
    2025-11-11 10:24:48 net_iface_new: add tun0 type ovpn-dco
    2025-11-11 10:24:48 DCO device tun0 opened
    ...
    2025-11-11 10:24:48 Initialization Sequence Completed
    ```

If you see **`DCO device tun0 opened`** (and *not* `TUN/TAP device tun0 opened`), your server is successfully running with Data Channel Offload.

## Available Scripts

This image uses the original `kylemanna` scripts, adapted to find the Debian `easyrsa` package.

* `ovpn_run`
    The main entrypoint. This script sets up networking (iptables, tun) and starts the OpenVPN process.

* `ovpn_genconfig`
    Generates the initial `openvpn.conf` server configuration file. This version is modified to be **DCO-compatible by default** (uses `topology subnet` and `allow-compression no`).

* `ovpn_initpki`
    Initializes the Public Key Infrastructure (PKI). It creates the Certificate Authority (CA), generates server keys/certificates, and creates DH parameters.

* `ovpn_getclient`
    Generates a unified `.ovpn` configuration file for a specific client, combining the configuration and keys.

* `ovpn_revokeclient`
    Revokes a client's certificate. This adds the client to the Certificate Revocation List (CRL), preventing them from connecting.

* `ovpn_listclients`
    Lists all generated client certificates, their validity status (VALID, EXPIRED, REVOKED), and expiration dates.

* `ovpn_getclient_all`
    A helper script that loops and exports `.ovpn` files (in both combined and separated formats) for *all* known clients.

* `ovpn_otp_user`
    Adds a new user for Google Authenticator (OTP/2FA). This only works if the server was configured with the `-2` flag in `ovpn_genconfig`.

* `ovpn_copy_server_files`
    Copies all necessary server files (keys, certs, config) to a target directory, often used for backups or clustering.

* `ovpn_status`
    Tails the OpenVPN status log (`/tmp/openvpn-status.log`), showing current connections in real-time.