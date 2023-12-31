#!/bin/bash
# Default values
OBSERVE_COLLECTION_ENDPOINT=""
OBSERVE_TOKEN=""
BRANCH="main"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --observe_collection_endpoint)
      OBSERVE_COLLECTION_ENDPOINT="$2"
      shift 2
      ;;
    --observe_token)
      OBSERVE_TOKEN="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$3"
      shift 2
      ;;
    *)
      echo "Unknown parameter: $1" >&2
      exit 1
      ;;
  esac
done

# Check if --host and --token are provided
if [ -z "$OBSERVE_COLLECTION_ENDPOINT" ] || [ -z "$OBSERVE_TOKEN" ]; then
  echo "Usage: $0 --observe_collection_endpoint OBSERVE_COLLECTION_ENDPOINT --observe_token OBSERVE_TOKEN"
  exit 1
fi

get_os(){
    if [ -f /etc/os-release ]; then
    . /etc/os-release

    OS=$( echo "${ID}" | tr '[:upper:]' '[:lower:]')
    CODENAME=$( echo "${VERSION_CODENAME}" | tr '[:upper:]' '[:lower:]')
elif lsb_release &>/dev/null; then
    OS=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
    CODENAME=$(lsb_release -cs)
else
    OS=$(uname -s)
fi

echo $OS
}

install_apt(){
    sudo apt-get -y install wget systemctl acl
    wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.90.1/otelcol-contrib_0.90.1_linux_amd64.deb
    sudo dpkg -i otelcol-contrib_0.90.1_linux_amd64.deb
}

install_yum(){
    sudo yum -y install wget systemctl
    wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.90.1/otelcol-contrib_0.90.1_linux_amd64.rpm
    sudo rpm -ivh otelcol-contrib_0.90.1_linux_amd64.rpm
}

configure_otel() {
    url=$1
    destination_dir=$2

    mkdir -p "$destination_dir"

    # Construct destination
    filename=$(basename "$url")
    destination="$destination_dir/$filename"

    curl -L "$url" -o "$destination"
}

config_urls=(
    "https://raw.githubusercontent.com/observeinc/host-config-scripts/${BRANCH}/opentelemetry/linux/config.yaml"
)

OS=$(get_os)

case ${OS} in
    amzn|amazonlinux|rhel|centos)
        install_yum
    ;;
    ubuntu|debian)
        install_apt
        sudo apt-get install acl -y
    ;;
esac

sudo setfacl -Rm u:otelcol-contrib:rX /var/log

for url in "${config_urls[@]}"; do
    configure_otel "$url" "/etc/otelcol-contrib"
done

env_file="/etc/otelcol-contrib/otelcol-contrib.conf"
echo "OBSERVE_COLLECTION_ENDPOINT=$(echo "$OBSERVE_COLLECTION_ENDPOINT" | sed 's/\/\?$//')" >> "$env_file"
echo "OBSERVE_TOKEN=$OBSERVE_TOKEN" >> "$env_file"

sudo systemctl enable otelcol-contrib
sudo systemctl restart otelcol-contrib
