#!/bin/bash
# Default values
OBSERVE_COLLECTION_ENDPOINT=""
OBSERVE_TOKEN=""
BRANCH="main"
UNINSTALL=""

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --observe_collection_endpoint)
      OBSERVE_COLLECTION_ENDPOINT="$2"
      OBSERVE_COLLECTION_ENDPOINT=$(echo "$OBSERVE_COLLECTION_ENDPOINT" | sed 's/\/\?$//')
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

create_config(){
    sudo mv "$config_file" "$config_file.ORIG"
    sudo tee "$config_file" > /dev/null << EOT
extensions:
  health_check:
connectors:
  count:
receivers:
  otlp:  # Define the "otlp" receiver
    protocols:
      http:
        max_request_body_size: 10485760

  filestats:
    include: /etc/otelcol-contrib/config.yaml
    collection_interval: 240m
    initial_delay: 60s

  filelog/config:
    include: [ /etc/otelcol-contrib/config.yaml ]
    start_at: beginning
    poll_interval: 5m
    multiline:
      line_end_pattern: ENDOFLINEPATTERN

  prometheus/internal:
    config:
      scrape_configs:
        - job_name: 'otel-collector'
          scrape_interval: 5s
          static_configs:
            - targets: ['0.0.0.0:8888']

  hostmetrics:
    collection_interval: 60s
    scrapers:
      cpu:
        metrics:
          system.cpu.utilization:
            enabled: true
      load:
      memory:
        metrics:
          system.memory.utilization:
            enabled: true
      disk:
      filesystem:
        metrics:
          system.filesystem.utilization:
            enabled: true
      network:
      paging:
        metrics:
          system.paging.utilization:
            enabled: true

  filelog:
    include: [/var/log/**/*.log, /var/log/syslog]
    include_file_path: true
    retry_on_failure:
      enabled: true
    max_log_size: 4MiB
    operators:
      - type: filter
        expr: 'body matches "otel-contrib"'

processors:
  
  transform/truncate:
    log_statements:
      - context: log
        statements:
          - truncate_all(attributes, 2047)
          - truncate_all(resource.attributes, 2047)

  memory_limiter:
    check_interval: 1s
    limit_percentage: 20
    spike_limit_percentage: 5
  
  batch:
  
  resourcedetection:
    detectors: [env, system]
    system:
      hostname_sources: ["os"]
      resource_attributes:
        host.id:
          enabled: true
  
  resourcedetection/cloud:
    detectors: ["gcp", "ec2", "azure"]
    timeout: 2s
    override: false

  resourcedetection/barebones:
    detectors: [env, system]
    system:
      hostname_sources: ["os"]
      resource_attributes:
        host.id:
          enabled: true
        host.name:
          enabled: false
        os.type:
          enabled: true

exporters:
  logging:
    # loglevel: "DEBUG"
  otlphttp:
    endpoint: "${OBSERVE_COLLECTION_ENDPOINT}/v2/otel"
    headers:
      authorization: "Bearer ${OBSERVE_TOKEN}"

service:
  pipelines:
    
    metrics:
      receivers: [hostmetrics, prometheus/internal,count]
      processors: [memory_limiter, resourcedetection, resourcedetection/cloud, batch]
      exporters: [logging, otlphttp]

    metrics/filestats:
       receivers: [filestats]
       processors: [resourcedetection, resourcedetection/cloud]
       exporters: [logging, otlphttp]
       
    logs/config:
       receivers: [filelog/config]
       processors: [memory_limiter, transform/truncate, resourcedetection, resourcedetection/cloud, batch]
       exporters: [logging, otlphttp]
       
    logs:
      receivers: [otlp, filelog]
      processors: [memory_limiter, transform/truncate, resourcedetection, resourcedetection/cloud, batch]
      exporters: [logging, otlphttp, count]

  extensions: [health_check]

EOT

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

OS=$(get_os)

case ${OS} in
    amzn|amazonlinux|rhel|centos)
        destination_dir="/etc/otelcol-contrib"
        config_file="${destination_dir}/config.yaml"
        install_yum
        sudo yum install acl -y
        create_config
    ;;
    ubuntu|debian)
        if [ "$UNINSTALL" = "true" ]; then
          uninstall_apt
          sudo apt -y remove acl
        else
          destination_dir="/etc/otelcol-contrib"
          config_file="${destination_dir}/config.yaml"
          
          install_apt
          
          sudo apt-get install acl -y
          
          create_config
          
          sudo setfacl -Rm u:otelcol-contrib:rX /var/log

          sudo systemctl enable otelcol-contrib
          sudo systemctl restart otelcol-contrib

        fi
    ;;
esac




