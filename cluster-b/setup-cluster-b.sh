#!/bin/bash

mkdir wazuh
cd /home/argus/wazuh

		#install certs and config
curl -sO https://packages.wazuh.com/4.14/wazuh-certs-tool.sh
wget https://raw.githubusercontent.com/s3dany0x/wazuh/refs/heads/main/cluster-b/config.yml;
bash ./wazuh-certs-tool.sh -A ./root-ca.pem ./root-ca.key;
tar -cvf ./wazuh-certificates.tar -C ./wazuh-certificates/ .
rm -rf ./wazuh-certificates


		#install packages and indexer
apt install -y coreutils
apt-get install -y gnupg apt-transport-https curl
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee /etc/apt/sources.list.d/wazuh.list
apt-get update

apt install -y wazuh-indexer;

		# install indexer config
wget -O /etc/wazuh-indexer/opensearch.yml https://raw.githubusercontent.com/s3dany0x/wazuh/refs/heads/main/cluster-b/indexer/opensearch.yml

		# deploy certs and run indexer
NODE_NAME=cb-wazuh-indexer
mkdir /etc/wazuh-indexer/certs
tar -xf ./wazuh-certificates.tar -C /etc/wazuh-indexer/certs/ ./$NODE_NAME.pem ./$NODE_NAME-key.pem ./admin.pem ./admin-key.pem ./root-ca.pem
mv -n /etc/wazuh-indexer/certs/$NODE_NAME.pem /etc/wazuh-indexer/certs/indexer.pem
mv -n /etc/wazuh-indexer/certs/$NODE_NAME-key.pem /etc/wazuh-indexer/certs/indexer-key.pem
chmod 500 /etc/wazuh-indexer/certs
chmod 400 /etc/wazuh-indexer/certs/*
chown -R wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/certs

systemctl daemon-reload
systemctl enable wazuh-indexer
systemctl start wazuh-indexer

until curl -sk https://wazuh-ccs.argus.local:9200 >/dev/null; do sleep 5; done
sleep 10

/usr/share/wazuh-indexer/bin/indexer-security-init.sh;
curl -k -u admin:admin https://cluster-b.argus.local:9200;
echo "-----------------------------Test Indexer Done-----------------------------";


		#install server(manager + filebeat) and edit config
apt-get -y install wazuh-manager filebeat ;
curl -so /etc/filebeat/filebeat.yml https://packages.wazuh.com/4.14/tpl/wazuh/filebeat/filebeat.yml

wget -O /etc/filebeat/filebeat.yml https://raw.githubusercontent.com/s3dany0x/wazuh/refs/heads/main/cluster-b/server/filebeat.yml

filebeat keystore create
echo admin | filebeat keystore add username --stdin --force
echo admin | filebeat keystore add password --stdin --force

curl -so /etc/filebeat/wazuh-template.json https://raw.githubusercontent.com/wazuh/wazuh/v4.14.0/extensions/elasticsearch/7.x/wazuh-template.json
chmod go+r /etc/filebeat/wazuh-template.json

curl -s https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.4.tar.gz | tar -xvz -C /usr/share/filebeat/module

NODE_NAME=cb-wazuh-server
mkdir /etc/filebeat/certs
tar -xf ./wazuh-certificates.tar -C /etc/filebeat/certs/ ./$NODE_NAME.pem ./$NODE_NAME-key.pem ./root-ca.pem
mv -n /etc/filebeat/certs/$NODE_NAME.pem /etc/filebeat/certs/filebeat.pem
mv -n /etc/filebeat/certs/$NODE_NAME-key.pem /etc/filebeat/certs/filebeat-key.pem
chmod 500 /etc/filebeat/certs
chmod 400 /etc/filebeat/certs/*
chown -R root:root /etc/filebeat/certs

/var/ossec/bin/wazuh-keystore -f indexer -k username -v admin
/var/ossec/bin/wazuh-keystore -f indexer -k password -v admin

wget -O /var/ossec/etc/ossec.conf https://raw.githubusercontent.com/s3dany0x/wazuh/refs/heads/main/cluster-b/server/ossec.conf

systemctl daemon-reload
systemctl enable wazuh-manager filebeat
systemctl start wazuh-manager filebeat
filebeat test output

