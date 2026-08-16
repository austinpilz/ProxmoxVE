#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: austinpilz
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://browsertrix.com | Github: https://github.com/webrecorder/browsertrix

APP="Browsertrix"
var_tags="${var_tags:-web-archiving}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-50}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/local/bin/helm ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

  msg_info "Updating Helm Repository"
  $STD helm repo update
  msg_ok "Updated Helm Repository"

  CURRENT_VERSION=$(helm list -n default -o json 2>/dev/null | \
    python3 -c "import sys,json; charts=json.load(sys.stdin); \
    print(next((c['chart'].replace('browsertrix-','') for c in charts if c['name']=='btrix'), 'unknown'))" 2>/dev/null || echo "unknown")
  LATEST_VERSION=$(helm search repo browsertrix/browsertrix --output json 2>/dev/null | \
    python3 -c "import sys,json; results=json.load(sys.stdin); \
    print(results[0]['version'] if results else 'unknown')" 2>/dev/null || echo "unknown")

  if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
    msg_ok "Already on latest version (${LATEST_VERSION})"
    exit
  fi

  msg_info "Upgrading Browsertrix ${CURRENT_VERSION} → ${LATEST_VERSION}"
  $STD helm upgrade btrix browsertrix/browsertrix \
    --namespace default \
    --reuse-values \
    --wait \
    --timeout 10m
  msg_ok "Upgraded Browsertrix to ${LATEST_VERSION}"

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:30870${CL}"
echo -e "${INFO}${YW}Default login: ${BGN}admin@example.com${CL} / ${YW}password: ${BGN}PASSW0RD!${CL}"
echo -e "${INFO}${RD}Change the default credentials immediately after first login!${CL}"
