#!/usr/bin/env bash
set -eu pipefail

${get_base64_secrets}
${install_packages}
%{ if enable_monitoring ~}
${install_monitoring_agents}
%{ endif ~}

log_pathname="/var/log/startup.log"

%{ if cloud == "google" && distribution == "rhel" ~}
echo "[Terraform Enterprise] Patching GCP Yum repo configuration" | tee -a $log_pathname
# workaround for GCP RHEL 7 known issue 
# https://cloud.google.com/compute/docs/troubleshooting/known-issues#keyexpired
sed -i 's/repo_gpgcheck=1/repo_gpgcheck=0/g' /etc/yum.repos.d/google-cloud.repo
%{ endif ~}

install_packages $log_pathname

echo "[$(date +"%FT%T")] [Terraform Enterprise] Install JQ" | tee -a $log_pathname
sudo curl --noproxy '*' -Lo /bin/jq https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
sudo chmod +x /bin/jq

%{ if cloud == "google" ~}
docker_directory="/etc/docker"
echo "[Terraform Enterprise] Creating Docker directory at '$docker_directory'" | tee -a $log_pathname
mkdir -p $docker_directory
docker_daemon_pathname="$docker_directory/daemon.json"
echo "[Terraform Enterprise] Writing Docker daemon to '$docker_daemon_pathname'" | tee -a $log_pathname
echo "${docker_config}" | base64 --decode > $docker_daemon_pathname
%{ endif ~}

%{ if proxy_ip != null ~}
echo "[$(date +"%FT%T")] [Terraform Enterprise] Configure proxy" | tee -a $log_pathname
proxy_ip="${proxy_ip}"
proxy_port="${proxy_port}"
/bin/cat <<EOF >>/etc/environment
http_proxy="${proxy_ip}:${proxy_port}"
https_proxy="${proxy_ip}:${proxy_port}"
no_proxy="${no_proxy}"
EOF

/bin/cat <<EOF >/etc/profile.d/proxy.sh
http_proxy="${proxy_ip}:${proxy_port}"
https_proxy="${proxy_ip}:${proxy_port}"
no_proxy="${no_proxy}"
EOF

export http_proxy="${proxy_ip}:${proxy_port}"
export https_proxy="${proxy_ip}:${proxy_port}"
export no_proxy="${no_proxy}"
%{ else ~}
echo "[$(date +"%FT%T")] [Terraform Enterprise] Skipping proxy configuration" | tee -a $log_pathname
%{ endif ~}

%{ if certificate_secret_id != null ~}
echo "[$(date +"%FT%T")] [Terraform Enterprise] Configure TlsBootstrapCert" | tee -a $log_pathname
certificate_data_b64=$(get_base64_secrets ${certificate_secret_id})
mkdir -p $(dirname ${tls_bootstrap_cert_pathname})
echo $certificate_data_b64 | base64 --decode > ${tls_bootstrap_cert_pathname}
%{ else ~}
echo "[$(date +"%FT%T")] [Terraform Enterprise] Skipping TlsBootstrapCert configuration" | tee -a $log_pathname
%{ endif ~}

%{ if key_secret_id != null ~}
echo "[$(date +"%FT%T")] [Terraform Enterprise] Configure TlsBootstrapKey" | tee -a $log_pathname
key_data_b64=$(get_base64_secrets ${key_secret_id})
mkdir -p $(dirname ${tls_bootstrap_key_pathname})
echo $key_data_b64 | base64 --decode > ${tls_bootstrap_key_pathname}
chmod 0600 ${tls_bootstrap_key_pathname}
%{ else ~}
echo "[$(date +"%FT%T")] [Terraform Enterprise] Skipping TlsBootstrapKey configuration" | tee -a $log_pathname
echo "[$(date +"%FT%T")] [Terraform Enterprise] Generating Self-Signed TlsBootstrapKey configuration" | tee -a $log_pathname
mkdir -p $(dirname ${tls_bootstrap_key_pathname})
cd $(dirname ${tls_bootstrap_key_pathname})
%{ if hostname != "localhost" ~}
openssl req -x509 -nodes -newkey rsa:4096 -keyout key.pem -out cert.pem -sha256 -days 365 -subj "/CN=${hostname}/L=Internal"
%{ else ~}
local_hostname=$(ec2metadata --local-hostname)
openssl req -x509 -nodes -newkey rsa:4096 -keyout key.pem -out cert.pem -sha256 -days 365 -subj "/CN=$local_hostname/L=Internal"
%{ endif ~}
cp cert.pem bundle.pem
%{ endif ~}
ca_certificate_directory="/dev/null"
%{ if distribution == "rhel" ~}
ca_certificate_directory=/usr/share/pki/ca-trust-source/anchors
%{ else ~}
ca_certificate_directory=/usr/local/share/ca-certificates/extra
%{ endif ~}
ca_cert_filepath="$ca_certificate_directory/tfe-ca-certificate.crt"
%{ if ca_certificate_secret_id != null ~}
echo "[$(date +"%FT%T")] [Terraform Enterprise] Configure CA cert" | tee -a $log_pathname
ca_certificate_data_b64=$(get_base64_secrets ${ca_certificate_secret_id})
mkdir -p $ca_certificate_directory
echo $ca_certificate_data_b64 | base64 --decode > $ca_cert_filepath
%{ else ~}
echo "[$(date +"%FT%T")] [Terraform Enterprise] Skipping CA certificate configuration" | tee -a $log_pathname
%{ endif ~}

if [ -f "$ca_cert_filepath" ]
then
%{ if distribution == "rhel" ~}
update-ca-trust
system_ca_certificate_file="/etc/pki/tls/certs/ca-bundle.crt"
%{ else ~}
update-ca-certificates
system_ca_certificate_file="/etc/ssl/certs/ca-certificates.crt"
%{ endif ~}
cp $ca_cert_filepath ${tls_bootstrap_ca_pathname}
tr -d "\\r" < "$ca_cert_filepath" >> "$system_ca_certificate_file"
fi

%{ if cloud == "azurerm" && distribution == "rhel" ~}
echo "[$(date +"%FT%T")] [Terraform Enterprise] Resize RHEL logical volume" | tee -a $log_pathname
terminal_partition=$(parted --script /dev/disk/cloud/azure_root u s p | tail -2 | head -n 1)
terminal_partition_number=$(echo $${terminal_partition:0:3} | xargs)
terminal_partition_link=/dev/disk/cloud/azure_root-part$terminal_partition_number
# Because Microsoft is publishing only LVM-partitioned images, it is necessary to partition it to the specs that TFE requires.
# First, extend the partition to fill available space
growpart /dev/disk/cloud/azure_root $terminal_partition_number
# Resize the physical volume
pvresize $terminal_partition_link
# Then resize the logical volumes to meet TFE specs
lvresize -r -L 10G /dev/mapper/rootvg-rootlv
lvresize -r -L 40G /dev/mapper/rootvg-varlv
%{ endif ~}

%{ if disk_path != null ~}
device="/dev/${disk_device_name}"
echo "[Terraform Enterprise] Checking disk at '$device' for EXT4 filesystem" | tee -a $log_pathname
if lsblk --fs $device | grep ext4
then
  echo "[Terraform Enterprise] EXT4 filesystem detected on disk at '$device'" | tee -a $log_pathname
else
  echo "[Terraform Enterprise] Creating EXT4 filesystem on disk at '$device'" | tee -a $log_pathname
  mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard $device -F
fi
echo "[Terraform Enterprise] Creating mounted disk directory at '${disk_path}'" | tee -a $log_pathname
mkdir --parents ${disk_path}
echo "[Terraform Enterprise] Mounting disk '$device' to directory at '${disk_path}'" | tee -a $log_pathname
mount --options discard,defaults $device ${disk_path}
chmod og+rw ${disk_path}
echo "[Terraform Enterprise] Configuring automatic mounting of '$device' to directory at '${disk_path}' on reboot" | tee -a $log_pathname
echo "UUID=$(lsblk --noheadings --output uuid $device) ${disk_path} ext4 discard,defaults 0 2" >> /etc/fstab
%{ endif ~}

%{ if enable_monitoring ~}
install_monitoring_agents $log_pathname
%{ endif ~}

echo "[$(date +"%FT%T")] [Terraform Enterprise] Installing Docker Engine from Repository" | tee -a $log_pathname
%{ if distribution == "rhel" ~}
/bin/cat <<EOF > /etc/yum/pluginconf.d/subscription-manager.conf
[main]
enabled=0
EOF
yum install --assumeyes yum-utils
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
os_release=$(cat /etc/os-release | grep VERSION_ID | sed "s/VERSION_ID=\"\(.*\)\"/\1/g")
if (( $(echo "$os_release < 8.0" | bc -l ) )); then
/bin/cat <<EOF >>/etc/yum.repos.d/docker-ce.repo
[centos-extras]
name=Centos extras - \$basearch
baseurl=http://mirror.centos.org/centos/7/extras/x86_64
enabled=1
gpgcheck=1
gpgkey=http://centos.org/keys/RPM-GPG-KEY-CentOS-7
EOF
fi
yum install --assumeyes docker-ce-${docker_version} docker-ce-cli-${docker_version} containerd.io docker-buildx-plugin docker-compose-plugin
systemctl start docker
%{ else ~}
curl --noproxy '*' --fail --silent --show-error --location https://download.docker.com/linux/ubuntu/gpg \
	| gpg --dearmor --output /usr/share/keyrings/docker-archive-keyring.gpg
echo \
	"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
	https://download.docker.com/linux/ubuntu $(lsb_release --codename --short) stable" \
	| sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get --assume-yes update
apt-get --assume-yes install docker-ce docker-ce-cli containerd.io
apt-get --assume-yes autoremove
%{ endif ~}

echo "[$(date +"%FT%T")] [Terraform Enterprise] Installing TFE FDO" | tee -a $log_pathname
hostname > /var/log/tfe-fdo.log
docker login -u="${registry_username}" -p="${registry_password}" images.releases.hashicorp.com

export HOST_IP=$(hostname -i)

tfe_dir="/etc/tfe"
mkdir -p $tfe_dir

cat > $tfe_dir/compose.yaml <<EOF
${compose}
EOF

docker compose -f /etc/tfe/compose.yaml up -d

%{ if distribution == "rhel" && cloud != "google" ~}
if (( $(echo "$os_release < 8.0" | bc -l ) )); then
  echo "[$(date +"%FT%T")] [Terraform Enterprise] Disable SELinux (temporary)" | tee -a $log_pathname
  setenforce 0
  echo "[$(date +"%FT%T")] [Terraform Enterprise] Add docker0 to firewalld" | tee -a $log_pathname
  firewall-cmd --permanent --zone=trusted --change-interface=docker0
  firewall-cmd --reload
  echo "[$(date +"%FT%T")] [Terraform Enterprise] Enable SELinux" | tee -a $log_pathname
  setenforce 1
fi
%{ endif ~}

%{ if custom_image_tag != null && cloud == "google" ~}
%{ if length(regexall("^.+-docker\\.pkg\\.dev|^.*\\.?gcr\\.io", custom_image_tag)) > 0 ~}
echo "[Terraform Enterprise] Registering gcloud as a Docker credential helper" | tee -a
gcloud auth configure-docker --quiet ${split("/", custom_image_tag)[0]}

%{ endif ~}
echo "[Terraform Enterprise] Pulling custom worker image '${custom_image_tag}'" | tee -a
docker pull ${custom_image_tag}
%{ endif ~}
