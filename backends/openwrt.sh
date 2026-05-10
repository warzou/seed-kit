#!/bin/sh

backend_name() {
  echo "openwrt"
}

backend_plan() {
  echo "- use opkg for packages later"
  echo "- keep shell strictly lightweight"
  echo "- V0 does not change firewall or network config"
}
