#!/bin/sh

backend_name() {
  echo "debian"
}

backend_plan() {
  echo "- use apt for packages"
  echo "- prefer systemctl when services are needed"
  echo "- keep configuration changes explicit"
}
