#!/bin/bash
# Default values
OBSERVE_COLLECTION_ENDPOINT=""
OBSERVE_TOKEN=""

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

# SYS_ARCH=$(uname -m)
# if [[ $SYS_ARCH = "aarch64" ]]; then
#     ARCH="arm64"
# else
#     ARCH="amd64"
# fi
}

install_apt(){
    # influxdata-archive_compat.key GPG Fingerprint: 9D539D90D3328DC7D6C8D3B9D8FF8E1F7DF8B07E
    curl -s https://repos.influxdata.com/influxdata-archive_compat.key > influxdata-archive_compat.key
    echo '393e8779c89ac8d958f81f942f9ad7fb82a25e133faddaf92e15b16e6ac9ce4c influxdata-archive_compat.key' | sha256sum -c && cat influxdata-archive_compat.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg > /dev/null
    echo 'deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg] https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdata.list
    sudo apt-get update && sudo apt-get install telegraf
}

install_yum(){
cat <<EOF | sudo tee /etc/yum.repos.d/influxdb.repo
[influxdb]
name = InfluxDB Repository - RHEL 7
baseurl = https://repos.influxdata.com/rhel/7/\$basearch/stable
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdata-archive_compat.key
EOF

    sudo yum install telegraf -y
}

configure_telegraf() {
    url=$1
    destination_dir=$2

    mkdir -p "$destination_dir"

    # Construct destination
    filename=$(basename "$url")
    destination="$destination_dir/$filename"

    curl -L "$url" -o "$destination"
}

config_urls=(
    "https://raw.githubusercontent.com/yasar-observe/host-configuration-scripts/yasar/init/telegraf/linux/telegraf.conf"
    "https://raw.githubusercontent.com/yasar-observe/host-configuration-scripts/yasar/init/telegraf/linux/observe_logs.conf"
    "https://raw.githubusercontent.com/yasar-observe/host-configuration-scripts/yasar/init/telegraf/linux/observe_metrics.conf"
    "https://raw.githubusercontent.com/yasar-observe/host-configuration-scripts/yasar/init/telegraf/linux/observe_custom.conf"
)

OS=$(get_os)

case ${OS} in
    amzn|amazonlinux|rhel|centos)
        install_yum
    ;;
    ubuntu|debian)
        install_apt
    ;;
esac

for url in "${config_urls[@]}"; do
    configure_telegraf "$url" "/etc/telegraf"
done

env_file="/etc/default/telegraf"
echo "OBSERVE_COLLECTION_ENDPOINT=$OBSERVE_COLLECTION_ENDPOINT" > "$env_file"
echo "OBSERVE_TOKEN=$OBSERVE_TOKEN" >> "$env_file"

sudo systemctl enable telegraf
sudo systemctl restart telegraf