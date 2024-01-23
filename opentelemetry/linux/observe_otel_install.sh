#!/bin/bash
# Default values
OBSERVE_COLLECTION_ENDPOINT=""
OBSERVE_TOKEN=""
BRANCH="main"
REPLACE_FILE=""
UNINSTALL=""

destination_dir="/etc/otelcol-contrib"
env_file="${destination_dir}/otelcol-contrib.conf"

echo "destination_dir = ${destination_dir}"
echo "env_file = ${env_file}"

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
    --uninstall)
      UNINSTALL="true"
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

uninstall_apt(){
    sudo dpkg --purge otelcol-contrib
    rm -fR "$destination_dir"
}

install_yum(){
    sudo yum -y install wget systemctl
    wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.90.1/otelcol-contrib_0.90.1_linux_amd64.rpm
    sudo rpm -ivh otelcol-contrib_0.90.1_linux_amd64.rpm
}

configure_otel() {
    url=$1

    mkdir -p "$destination_dir"

    # Construct destination
    filename=$(basename "$url")
    destination="$destination_dir/$filename"

    sudo rm -f "$destination"
    sudo rm -f "$env_file"
    
    curl -L "$url" | sudo tee "$destination" >> /dev/null
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
        if [ "$UNINSTALL" = "true" ]; then
          uninstall_apt
        else
          install_apt
          sudo apt-get install acl -y
        fi
    ;;
esac

sudo setfacl -Rm u:otelcol-contrib:rX /var/log

for url in "${config_urls[@]}"; do
    configure_otel "$url"
done

sudo mv $destination_dir/config.yaml $destination_dir/config.ORIG
sudo mv $destination_dir/otelcol-contrib.conf $destination_dir/otelcol-contrib.ORIG


echo "OBSERVE_COLLECTION_ENDPOINT=$(echo "$OBSERVE_COLLECTION_ENDPOINT" | sed 's/\/\?$//')" | sudo tee -a "$env_file" >> /dev/null
echo "OBSERVE_TOKEN=$OBSERVE_TOKEN" | sudo tee -a "$env_file" >> /dev/null
# cd "$destination_dir"



# sudo sed -i "s,OBSERVE_COLLECTION_ENDPOINT,$OBSERVE_COLLECTION_ENDPOINT,g" ./*
# sudo sed -i "s,OBSERVE_TOKEN,$OBSERVE_TOKEN,g" ./*

# sudo setfacl -Rm u:otelcol-contrib:rX "$destination_dir"

sudo systemctl enable otelcol-contrib
sudo systemctl restart otelcol-contrib


