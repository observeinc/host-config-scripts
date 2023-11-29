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

config_urls=(
    "https://raw.githubusercontent.com/yasar-observe/host-configuration-scripts/yasar/init/fluent-bit/linux/fluent-bit.conf"
    "https://raw.githubusercontent.com/yasar-observe/host-configuration-scripts/yasar/init/fluent-bit/linux/observe_logs.conf"
    "https://raw.githubusercontent.com/yasar-observe/host-configuration-scripts/yasar/init/fluent-bit/linux/observe_metrics.conf"
    "https://raw.githubusercontent.com/yasar-observe/host-configuration-scripts/yasar/init/fluent-bit/linux/observe_custom.conf"
)

install_fluent() {
    curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sudo sh
}

configure_fluent() {
    url=$1
    destination_dir=$2

    mkdir -p "$destination_dir"

    # Construct destination
    filename=$(basename "$url")
    destination="$destination_dir/$filename"

    curl -L "$url" -o "$destination"
}

sanitize_url() {
    local url="$1"
    local sanitized_url

    # Remove "http://"
    sanitized_url=$(echo "$url" | sed 's/^http:\/\///')

    # Remove trailing forward slash
    sanitized_url=$(echo "$sanitized_url" | sed 's/\/$//')

    echo "$sanitized_url"
}


SANITIZED_HOST=$(sanitize_url "$OBSERVE_COLLECTION_ENDPOINT")
env_file="/etc/sysconfig/fluent-bit"

echo "OBSERVE_COLLECTION_ENDPOINT=$SANITIZED_HOST" > "$env_file"
echo "OBSERVE_TOKEN=$OBSERVE_TOKEN" >> "$env_file"

install_fluent

for url in "${config_urls[@]}"; do
    configure_fluent "$url" "/etc/fluent-bit"
done

sudo systemctl enable fluent-bit
sudo systemctl restart fluent-bit