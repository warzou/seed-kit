#!/bin/sh

backend_name() {
  echo "raspberrypi"
}

backend_plan() {
  echo "- use apt for packages"
  echo "- keep RAM usage low"
  echo "- avoid desktop assumptions"
}
