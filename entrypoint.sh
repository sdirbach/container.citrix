#!/bin/bash

if [ ! -z "$GATEWAY_ADDRESS" ]; then
    ip r d default 
    ip r a default via $GATEWAY_ADDRESS
fi

if [ ! -z "$http_proxy" ] || [ ! -z "$https_proxy" ]; then
  proxyBase='{"Mode":"manual","Locked":true,"UseHTTPProxyForAllProtocols":false,"UseProxyForDNS":false}'
  proxyHttp='{"HTTPProxy": "hostname"}'
  proxySSL='{"SSLProxy": "hostname"}'
    
  if [ ! -z "$http_proxy" ]; then
    proxyHttpHost=$(awk -F/ '{print $3}' <<<$http_proxy)
    proxyHttp=$(jq --arg jq_proxyHttpHost $proxyHttpHost '.HTTPProxy = $jq_proxyHttpHost' <<<$proxyHttp)
    proxyBase=$(jq --argjson jq_proxyHttp "$proxyHttp" '. +$jq_proxyHttp' <<<$proxyBase)
  fi
  if [ ! -z "$https_proxy" ]; then
    proxySSLHost=$(awk -F/ '{print $3}' <<<$https_proxy)
    proxySSL=$(jq --arg jq_proxySSLHost $proxySSLHost '.SSLProxy = $jq_proxySSLHost' <<<$proxySSL)
    proxyBase=$(jq --argjson jq_proxyHttp "$proxySSL" '. +$jq_proxyHttp' <<<$proxyBase)

    # Configure Citrix for HTTPS Proxy
    proxySSLHostDNS=$(awk -F: '{print $1}' <<<$proxySSLHost)
    proxySSLHostPort=$(awk -F: '{print $2}' <<<$proxySSLHost)
    citrixAllRegions='/opt/Citrix/ICAClient/config/All_Regions.ini'

    sed 's/${HDXoverUDP}/Off/g' $citrixAllRegions | sponge $citrixAllRegions
    sed 's/${ProxyType}/Secure/g' $citrixAllRegions | sponge $citrixAllRegions
    sed 's/${ProxyHost}/'$proxySSLHostDNS'/g' $citrixAllRegions | sponge $citrixAllRegions
    sed 's/${ProxyPort}/'$proxySSLHostPort'/g' $citrixAllRegions | sponge $citrixAllRegions
  else
    sed 's/${HDXoverUDP}//g' $citrixAllRegions | sponge $citrixAllRegions
    sed 's/${ProxyType}//g' $citrixAllRegions | sponge $citrixAllRegions
    sed 's/${ProxyHost}//g' $citrixAllRegions | sponge $citrixAllRegions
    sed 's/${ProxyPort}//g' $citrixAllRegions | sponge $citrixAllRegions
  fi

  policies=$(jq --argjson jq_proxy "$proxyBase" '.policies + {"Proxy": $jq_proxy}' /usr/lib64/firefox/distribution/policies.json)
  jq --argjson jq_policies "$policies" '.policies = $jq_policies' /usr/lib64/firefox/distribution/policies.json | sponge /usr/lib64/firefox/distribution/policies.json 
fi 

mkdir -p /tmp/.ICAClient
touch /tmp/.ICAClient/.eula_accepted

mkdir -p /tmp/firefox/profile

if [ ! -z "$FIREFOX_PROFILE" ]; then
  if [ ! -d "/tmp/firefox/profile/$FIREFOX_PROFILE" ]; then
    firefox -CreateProfile "$FIREFOX_PROFILE /tmp/firefox/profile/$FIREFOX_PROFILE"
  fi
  firefox --new-instance -profile "/tmp/firefox/profile/$FIREFOX_PROFILE"
else
  firefox --new-instance
fi

echo "Firefox closed"

# Check if wfica is (still) running, exit otherwise
while true;
do
  sleep 1
  PROC_COUNT=$(ps -o command --no-headers --ppid 1|grep wfica|wc -l)
  if [ "$PROC_COUNT" -eq "0" ]; then
    echo "Citrix client wfica not found"
    break
  fi
done

echo "Exiting..."
