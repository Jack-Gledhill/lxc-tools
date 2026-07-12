#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# NVIDIA DRIVER & CONTAINER TOOLKIT INSTALLER
# ----------------------------------------------------------------------------
# Copyright (c) 2026 Jack Gledhill
# Author: Jack Gledhill
# License: GPLv3 | https://github.com/Jack-Gledhill/lxc-tools/raw/main/LICENSE
# ----------------------------------------------------------------------------

set -eo pipefail # Stops execution if any command fails

# -----------------------------------------------------------------------------------------
# Copyright (c) 2021-2026 community-scripts ORG
# License: MIT | https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/LICENSE
# shellcheck source=https://github.com/community-scripts/ProxmoxVE/raw/refs/heads/main/misc/core.func
source <(curl -fsSL https://github.com/community-scripts/ProxmoxVE/raw/refs/heads/main/misc/core.func)
load_functions
# shellcheck source=https://github.com/community-scripts/ProxmoxVE/raw/refs/heads/main/misc/tools.func
source <(curl -fsSL https://github.com/community-scripts/ProxmoxVE/raw/refs/heads/main/misc/tools.func)
# -----------------------------------------------------------------------------------------

usage() {
    cat << EOF
usage: $0 [-d VERSION] [-n VERSION] [-h]

This script assumes that the container is running a 64-bit x86 Linux distribution.

This script downloads and installs the userspace libraries of the NVIDIA proprietary drivers.
The driver version to download must be configured by using the -d flag.

Once the driver has been installed, this script can also be used to install the NVIDIA Container Toolkit,
which is necessary for using your GPU in nested container workloads (e.g. Docker).
The version to download must be given via the -n flag, otherwise this step is skipped.
As part of the installation, the NVIDIA Container Toolkit APT repository is also installed.
Once installed, the NVIDIA Container Toolkit is automatically configured for the Docker runtime.

OPTIONS:
   -d, --driver-version VERSION  The NVIDIA driver version to install. If no version is given, this step is skipped.
   -n, --nct-version    VERSION  The NVIDIA Container Toolkit version to install. This step is skipped if no version is given.
   -h, --help                    Shows this message and exits.
EOF
}

DRIVER_VERSION=""
NCT_VERSION=""

PARAMS=""
while (( "$#" )); do
    case "$1" in
        -d|--driver-version)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                DRIVER_VERSION=$2
                shift 2
            else
                msg_error "Argument for $1 is missing"
                exit 1
            fi
            ;;
        -n|--nct-version)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                NCT_VERSION=$2
                shift 2
            else
                msg_error "Argument for $1 is missing"
                exit 1
            fi
            ;;
        -h|--help)
            usage
            exit 1
            ;;
        -*|--*=)
            msg_error "Unrecognised flag $1"
            exit 1
            ;;
        *) # Preserve positional arguments
            PARAMS="$PARAMS $1"
            shift
            ;;
    esac
done
# Reset the positions of positional arguments
eval set -- "$PARAMS"

install_prerequisites() {
    apt-get install -qq -y \
        curl \
        gnupg2 \
        ca-certificates
}

install_driver() {
    local filename="NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"
    local filepath="$PWD/${filename}"

    msg_info "Downloading NVIDIA driver version ${DRIVER_VERSION}..."
    curl_with_retry "https://us.download.nvidia.com/XFree86/Linux-x86_64/${DRIVER_VERSION}/${filename}" "${filepath}"
    chmod +x "${filepath}"
    msg_ok "Downloaded NVIDIA driver version ${DRIVER_VERSION} and saved to ${filepath}"

    msg_info "Running NVIDIA driver installer, this may take a while..."
    bash "${filepath}" --no-kernel-modules -q --ui=none
    msg_ok "Driver installer finished"

    rm "${filepath}"
    msg_ok "Cleaned up driver installation"
}

install_nct_repo() {
    msg_info "Configuring NVIDIA Container Toolkit deb repository..."
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    cat > /etc/apt/sources.list.d/nvidia.sources <<EOF
Types: deb
URIs: https://nvidia.github.io/libnvidia-container/stable/deb/amd64
Suites: /
Components:
Signed-By: /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
EOF
    msg_ok "Container Toolkit repository ready"
}

install_nct() {
    msg_info "Installing NVIDIA Container Toolkit version ${NCT_VERSION}..."
    apt-get update -qq
    apt-get install -qq -y \
        nvidia-container-toolkit="${NCT_VERSION}" \
        nvidia-container-toolkit-base="${NCT_VERSION}" \
        libnvidia-container-tools="${NCT_VERSION}" \
        libnvidia-container1="${NCT_VERSION}"

    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
    msg_ok "Successfully installed NVIDIA Container Toolkit version ${NCT_VERSION}"
}

install_prerequisites

if [ -z "${DRIVER_VERSION}" ]; then
    msg_warn "No driver version given, installation will be skipped"
else
    install_driver
fi

if [ -z "${NCT_VERSION}" ]; then
    msg_warn "No NVIDIA Container Toolkit version given, installation will be skipped"
else
    install_nct_repo
    install_nct
fi