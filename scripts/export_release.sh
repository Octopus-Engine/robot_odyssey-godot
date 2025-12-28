#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

sh ${SCRIPT_DIR}/export_release_linux.sh
sh ${SCRIPT_DIR}/export_release_windows.sh
#sh ${SCRIPT_DIR}/export_web.sh
