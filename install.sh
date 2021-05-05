#!/bin/bash

read -p 'Enter domain name for node (ex: node01.test.com: ' DOMAIN
echo Configuring for domain: $DOMAIN

MAIN_SEEDS=03b74fa3c68356bb40d58ecc10129479b159a145@seed1.mainnet.pokt.network:20656,64c91701ea98440bc3674fdb9a99311461cdfd6f@seed2.mainnet.pokt.network:21656,0057ee693f3ce332c4ffcb499ede024c586ae37b@seed3.mainnet.pokt.network:22856,9fd99b89947c6af57cd0269ad01ecb99960177cd@seed4.mainnet.pokt.network:23856,1243026603e9073507a3157bc4de99da74a078fc@seed5.mainnet.pokt.network:24856,6282b55feaff460bb35820363f1eb26237cf5ac3@seed6.mainnet.pokt.network:25856,3640ee055889befbc912dd7d3ed27d6791139395@seed7.mainnet.pokt.network:26856,1951cded4489bf51af56f3dbdd6df55c1a952b1a@seed8.mainnet.pokt.network:27856,a5f4a4cd88db9fd5def1574a0bffef3c6f354a76@seed9.mainnet.pokt.network:28856,d4039bd71d48def9f9f61f670c098b8956e52a08@seed10.mainnet.pokt.network:29856,5c133f07ed296bb9e21e3e42d5f26e0f7d2b2832@poktseed100.chainflow.io:26656
TEST_SEEDS=b3d86cd8ab4aa0cb9861cb795d8d154e685a94cf@seed1.testnet.pokt.network:20656,17ca63e4ff7535a40512c550dd0267e519cafc1a@seed2.testnet.pokt.network:21656,f99386c6d7cd42a486c63ccd80f5fbea68759cd7@seed3.testnet.pokt.network:22656

read -p 'Use seeds for Mainnet or Testnet (m/T): ' M_T_NETWORK

M_T_NETWORK=${M_T_NETWORK^^}
if [[ "$M_T_NETWORK" == "M" ]]; then
    echo "Mainnet"
    SEEDS=$MAIN_SEEDS
else
    echo "Testnet"
    M_T_NETWORK="T"
    SEEDS=$TEST_SEEDS
fi

echo Seeds to be used: $SEEDS

read -p 'Use RC-0.6.1? n=use Beta-0.5.2.9 (Y/n): ' RC6_YN
RC6_YN=${RC6_YN^^}
if [[ "$RC6_YN" == "N" ]]; then
    echo "Using BETA-0.5.2.9"
    RC6_YN="N"
else
    echo "Using RC-0.6.1"
    RC6_YN="Y"
fi



g install 1.13
go get -u github.com/pokt-network/pocket-core
sudo apt-get update -y 
sudo apt-get install libleveldb-dev build-essential -y
cd ~/go/src/github.com/pokt-network/pocket-core
if [[ "$RC6_YN" == "N" ]]; then
   git checkout tags/Beta-0.5.2.9
else
   git checkout tags/RC-0.6.1
fi

echo $GOPATH

if [ -z "$GOPATH" ]
then
      echo "\$GOPATH is empty...Something is wrong!!"
      exit 1
else
      echo "\$GOPATH is set to: $GOPATH"
      echo PROCEEDING...
fi

go build -o $GOPATH/bin/pocket ./app/cmd/pocket_core/main.go

sleep 2
if [[ "$M_T_NETWORK" == "M" ]]; then
   pocket start --mainnet #creates config.json
else 
   pocket start --testnet #creates config.json
fi
PID=$(pgrep -f "pocket start")
kill $PID
sleep 2
cd ~/.pocket/config/
if [[ "$M_T_NETWORK" == "M" ]]; then
     curl -O https://raw.githubusercontent.com/pokt-network/pocket-network-genesis/master/mainnet/genesis.json
else
     curl -O https://raw.githubusercontent.com/pokt-network/pocket-network-genesis/master/testnet/genesis.json
fi

# Add  Create Chains
cd ~

CONFIG=~/.pocket/config/config.json
if [ -f "$CONFIG" ]; then
    echo "$CONFIG exists."
    echo CONTINUING...
else
    echo "$CONFIG does not exist. Exiting..."
    exit 1
fi

echo TRANSFORMING $CONFIG...

sed -i 's/\"rpc_port\":.*/\"rpc_port\": '\"8082'\",/g' $CONFIG
sed -i 's+\"remote_cli_url\":.*+\"remote_cli_url\": '\"http://localhost:8082'\",+g' $CONFIG
sed -i 's+\"Seeds\":.*+\"Seeds\": '\"$SEEDS'\",+g' $CONFIG

BASHRC=~/.bashrc
if cat $BASHRC | grep "ulimit -Sn 16384"; then
	echo ulimit setting already in $BASHRC
else
	echo Adding ulimit setting to $BASHRC...
	echo ulimit -Sn 16384 >> $BASHRC
fi

BASHRC=~/.bashrc
if cat $BASHRC | grep "export GODEBUG"; then
	echo GODEBUG setting already in $BASHRC
else
	echo Adding GODEBUG setting to $BASHRC...
	echo 'export GODEBUG="madvdontneed=1"' >> $BASHRC
fi

source ~/.bashrc

echo "Updating Go to V 1.16"
g install 1.16

echo NGINX CONFIGURATION
sudo service nginx start

if sudo service nginx status | grep "running"; then
	echo NGINX IS STARTED!
#	sudo service nginx status
else
	echo "NGINX NOT STARTED OR INSTALLED (Run sudo service nginx start)"
fi
# Add Curl on localhost:80

echo POPULATING pocket-proxy.conf FILE...

sudo bash -c 'cat > /etc/nginx/sites-available/pocket-proxy.conf  <<EOF
server {
   add_header Access-Control-Allow-Origin "*";
   listen 443 ssl;
   listen [::]:443 ssl;
   listen 8081 ssl;
   listen [::]:8081 ssl;
#   ssl on;
   ssl_certificate /etc/letsencrypt/live/changeThis.com/fullchain.pem;
   ssl_certificate_key /etc/letsencrypt/live/changeThis.com/privkey.pem;
   access_log /var/log/nginx/reverse-access.log;
   error_log /var/log/nginx/reverse-error.log;
    location ~* ^/v1/client/(dispatch|relay|challenge|sim) {
     proxy_pass http://127.0.0.1:8082;
     add_header Access-Control-Allow-Methods "POST, OPTIONS";
     allow all;
   }
   location = /v1 {
     add_header Access-Control-Allow-Methods "GET";
     proxy_pass http://127.0.0.1:8082;
     allow all;
   }
}
EOF'

PROXY_CONF=/etc/nginx/sites-available/pocket-proxy.conf

sudo sed -i "s/changeThis.com/$DOMAIN/g" $PROXY_CONF

sudo cat $PROXY_CONF

sudo ln -s /etc/nginx/sites-available/pocket-proxy.conf /etc/nginx/sites-enabled/pocket-proxy.conf

sudo systemctl stop nginx
sudo systemctl start nginx

if sudo service nginx status | grep "running"; then
        echo NGINX IS RESTARTED!
#       sudo service nginx status
else
        echo "NGINX NOT STARTED PROPERLY"
	exit 1
fi

echo CONFIGURATION COMPLETE - PROCEED TO STEP 5


#curl https://$DOMAIN:8081/v1

