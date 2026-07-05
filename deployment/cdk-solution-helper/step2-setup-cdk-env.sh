#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

shopt -s expand_aliases

# Pin pip to a known-good version that supports the Python 3.14 runtime.
# Keep this in sync with step1-build-lambda-pkg.sh.
pip_ver="26.1.2"

repo_root="${PWD}/../.."
source_template_dir="$PWD/../"
source_dir="$source_template_dir/../source"
cdk_version=$(grep aws-cdk-lib "${source_dir}/cdk/requirements.txt" | awk -F'==' '{print $2}')

is_al2=$(grep -oi Karoo /etc/system-release 2> /dev/null)
is_al2023=$(grep -oi "Amazon Linux release 2023" /etc/system-release 2> /dev/null)
if [ -n "$is_al2" ]; then
    echo "ERROR: Amazon Linux 2 is not supported. This solution requires Python 3.13 or later," >&2
    echo "       which is not available on Amazon Linux 2. Please use Amazon Linux 2023." >&2
    exit 1
fi
if [ -z "$is_al2023" ]; then
    echo "This is not Amazon Linux 2023."
    read -rp "Do you realy continue? (y/N): " yn
    case "$yn" in [yY]*) ;; *) echo "abort." ; exit ;; esac
fi

# Node.js
echo "AWS_EXECUTION_ENV is ${AWS_EXECUTION_ENV}"
echo -e ""
if [[ "${AWS_EXECUTION_ENV}" = "CloudShell" ]]; then
  echo "This environment is CloudShell"
  echo "Skip Node.js installation"
else
  MAJOR_VER=$(node -v 2>/dev/null | cut -f 2 -d v | cut -f 1 -d ".")
  # AWS CDK supports Node.js LTS versions 20.x, 22.x and 24.x.
  # Accept an already-installed supported version; otherwise install Node 24
  # (the newest Active LTS, supported until 2028-10-30).
  if [ "$MAJOR_VER" == "20" ] || [ "$MAJOR_VER" == "22" ] || [ "$MAJOR_VER" == "24" ]; then
    echo "Installed Node.js version is $MAJOR_VER "
    echo "Skip Node.js installation"
  else
    echo "Install Node.js"
    # shellcheck disable=SC1090
    nvm -v 2>/dev/null || curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash && source ~/.nvm/nvm.sh
    MAJOR_VER=$(node -v 2>/dev/null | cut -f 2 -d v | cut -f 1 -d ".")

    echo "Start installing Node 24"
    nvm install 24
    nvm alias default 24
    nvm use 24
    echo "nvm alias"
    nvm alias
  fi
fi

node -e "console.log('Running Node.js: ' + process.version)"
echo -e ""

# CDK CLI (aws-cdk)
# Since Feb 2025 the CDK CLI (aws-cdk) and the Construct Library (aws-cdk-lib)
# are released independently and their version numbers no longer match.
# The CLI now uses its own 2.1000.0+ version line. A given aws-cdk-lib is
# compatible with the CLI that was current at its release AND any newer CLI,
# so we always install the latest 2.x CLI ("^2") rather than pinning it to
# the aws-cdk-lib version.
echo "Install CDK CLI (latest aws-cdk@^2; independent from aws-cdk-lib ${cdk_version})"
if [[ "${AWS_EXECUTION_ENV}" = "CloudShell" ]]; then
  echo "npm install aws-cdk@^2"
  npm install aws-cdk@^2
else
  echo "npm install -g aws-cdk@^2"
  npm install -g aws-cdk@^2
fi

# create virtual venv
cd "$repo_root" || exit

# The AWS CDK runs on any Python >= 3.13, so use what is already
# installed (e.g. Python 3.13 on AWS CloudShell) instead of requiring
# python3.14 to be installed.
if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 13) else 1)' >/dev/null 2>&1; then
  :
elif [ -f "/usr/bin/python3.14" ]; then
  alias python3='/usr/bin/python3.14'
elif [ -f "/usr/bin/python3.13" ]; then
  alias python3='/usr/bin/python3.13'
elif [ -f "/usr/bin/python3.11" ]; then
  alias python3='/usr/bin/python3.11'
elif [ -f "/usr/bin/python3.10" ]; then
  alias python3='/usr/bin/python3.10'
else
  :
fi

local_version=$(python3 --version)
venv_version=$(.venv/bin/python --version 2>/dev/null)
echo "python local version: $local_version"
echo "python venv version: $venv_version"
if [ -n "$venv_version" ] && [ "$local_version" != "$venv_version" ]; then
  echo "delete .venv to install newer version"
  rm -fr .venv
fi
if [ ! -d .venv ]; then
  echo "create .venv"
  echo "python3 -m venv .venv"
  python3 -m venv .venv
fi
unalias python3 2>/dev/null
# shellcheck disable=SC1091
source .venv/bin/activate
python3 -m pip install wheel pip=="$pip_ver" --disable-pip-version-check --no-python-version-warning

# shellcheck disable=SC1091
echo "python3 -m pip install -r ${source_dir}/cdk/requirements.txt --disable-pip-version-check --no-python-version-warning"
python3 -m pip install -r "${source_dir}/cdk/requirements.txt" --disable-pip-version-check --no-python-version-warning

# Delete CDK v1
cd "${source_dir}/cdk" || exit
if [ -d .env ]; then
  echo "CDK v1 exists."
  echo "rm -fr .env"
  rm -fr .env
fi
if [ -d "${source_template_dir}/cdk-solution-helper/cdk.out" ]; then
  rm -fr "${source_template_dir}/cdk-solution-helper/cdk.out"
fi
