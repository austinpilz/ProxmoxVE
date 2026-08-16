#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: austinpilz
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://browsertrix.com | Github: https://github.com/webrecorder/browsertrix

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  curl \
  ca-certificates \
  git \
  iptables \
  ipset \
  python3
msg_ok "Installed Dependencies"

msg_info "Configuring Kernel Settings for K3s"
cat <<'EOF' >/etc/sysctl.d/99-k3s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl -p /etc/sysctl.d/99-k3s.conf 2>/dev/null || true

# K3s kubelet needs /dev/kmsg; in LXC containers it may not exist.
if [ ! -e /dev/kmsg ]; then
  ln -sf /dev/console /dev/kmsg
fi

# Ensure /dev/kmsg symlink survives reboots via rc.local
if ! grep -q "kmsg" /etc/rc.local 2>/dev/null; then
  cat <<'EOF' >/etc/rc.local
#!/bin/sh -e
[ -e /dev/kmsg ] || ln -sf /dev/console /dev/kmsg
exit 0
EOF
  chmod +x /etc/rc.local
fi
msg_ok "Configured Kernel Settings"

msg_info "Installing K3s (Lightweight Kubernetes)"
curl -sfL https://get.k3s.io -o /tmp/k3s-install.sh
export K3S_KUBECONFIG_MODE="644"
export INSTALL_K3S_EXEC="--disable=traefik"
$STD sh /tmp/k3s-install.sh
rm -f /tmp/k3s-install.sh
unset K3S_KUBECONFIG_MODE INSTALL_K3S_EXEC
msg_ok "Installed K3s"

msg_info "Waiting for K3s to be Ready"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
READY=false
for i in $(seq 1 36); do
  if kubectl get nodes 2>/dev/null | grep -q " Ready"; then
    READY=true
    break
  fi
  sleep 5
done
if [[ "$READY" != "true" ]]; then
  msg_error "K3s did not become ready within 3 minutes"
  exit 1
fi
msg_ok "K3s is Ready"

msg_info "Installing Helm"
$STD curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
msg_ok "Installed Helm"

msg_info "Adding Browsertrix Helm Repository"
$STD helm repo add browsertrix https://docs.browsertrix.com/helm-repo/
$STD helm repo update
msg_ok "Added Browsertrix Helm Repository"

msg_info "Generating Secure Secrets"
MONGO_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | cut -c1-20)
MINIO_SECRET=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | cut -c1-20)
BACKEND_SECRET=$(openssl rand -base64 36 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
msg_ok "Generated Secure Secrets"

msg_info "Creating Browsertrix Values Configuration"
mkdir -p /etc/browsertrix
cat <<EOF >/etc/browsertrix/values.yaml
superuser:
  email: "admin@example.com"
  password: "PASSW0RD!"

backend_password_secret: "${BACKEND_SECRET}"

mongo_auth:
  username: "root"
  password: "${MONGO_PASSWORD}"

storages:
  - name: "default"
    access_key: "ADMIN"
    secret_key: "${MINIO_SECRET}"
    bucket_name: "btrix"
    endpoint_url: ""
    region: ""

registration_enabled: false
EOF
chmod 600 /etc/browsertrix/values.yaml
msg_ok "Created Browsertrix Values Configuration"

msg_info "Deploying Browsertrix via Helm (this may take 5-10 minutes)"
$STD helm upgrade --install btrix browsertrix/browsertrix \
  --namespace default \
  --values /etc/browsertrix/values.yaml \
  --wait \
  --timeout 10m
msg_ok "Deployed Browsertrix"

msg_info "Waiting for All Pods to be Running"
kubectl wait --for=condition=ready pod --all --namespace default --timeout=300s 2>/dev/null || \
  msg_warn "Some pods may still be initializing; check with: kubectl get pods"
msg_ok "Browsertrix Pods are Running"

msg_info "Configuring Shell Environment"
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >>/root/.bashrc
cat <<'EOF' >/usr/local/bin/btrix-status
#!/usr/bin/env bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get pods --all-namespaces
EOF
chmod +x /usr/local/bin/btrix-status
msg_ok "Configured Shell Environment"

motd_ssh
customize
cleanup_lxc
