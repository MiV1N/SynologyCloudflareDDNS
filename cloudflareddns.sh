#!/bin/bash
set -e;

ipv4Regex="((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])"
ipv6="true"
# proxy="true" 
# ask for existing proxy, don't override it <.<

# DSM Config
username="$1"
password="$2"
hostname="$3"
ipAddr="$4"

get_ipv6_address() {
    local ip6Addr="" # 在函数内部使用 local 声明变量
    ip -6 addr show ovs_eth1 | awk '/inet6.*scope global/ {print $2}' | cut -d/ -f1 | while read ip; do
        local prefix=$(echo "$ip" | cut -d: -f1) # local 变量
        local prefix_int=$((16#$prefix))
        if (( prefix_int >= 0x2000 && prefix_int <= 0x3fff )); then
            echo "$ip" # 输出到标准输出
            return 0
        fi
    done
    return 1
}



#Fetch and filter IPv6, if Synology won't provide it
if [[ $ipv6 = "true" ]]; then

	ip6Addr=$(get_ipv6_address)
	recType6="AAAA"

	if [[ -z "$ip6Addr" ]]; then
		ipv6="false"; 	# if only ipv4 is available
	fi
	if [[ $ipAddr =~ $ipv4Regex ]]; then
		recordType="A";
	else
		recordType="AAAA";
		ipv6="false"; # because, Synology had provided the IPv6
	fi
else
	recordType="A";
fi

# Cloudflare API-Calls for listing entries
listDnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records?type=${recordType}&name=${hostname}"
# above only, if IPv4 and/or IPv6 is provided
listDnsv6Api="https://api.cloudflare.com/client/v4/zones/${username}/dns_records?type=${recType6}&name=${hostname}" # if only IPv4 is provided

res=$(curl -s -X GET "$listDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json")
resSuccess=$(echo "$res" | jq -r ".success")


if [[ $ipv6 = "true" ]]; then ## Adding new commands, if Synology didn't provided IPv6
resv6=$(curl -s -X GET "$listDnsv6Api" -H "Authorization: Bearer $password" -H "Content-Type:application/json");
fi

if [[ $resSuccess != "true" ]]; then
    echo "badauth";
    exit 1;
fi

recordId=$(echo "$res" | jq -r ".result[0].id")
recordIp=$(echo "$res" | jq -r ".result[0].content")
recordProx=$(echo "$res" | jq -r ".result[0].proxied")
if [[ $ipv6 = "true" ]]; then
recordIdv6=$(echo "$resv6" | jq -r ".result[0].id");
recordIpv6=$(echo "$resv6" | jq -r ".result[0].content");
recordProxv6=$(echo "$resv6" | jq -r ".result[0].proxied");
fi

# API-Calls for creating DNS-Entries
createDnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records" # does also work for IPv6


# API-Calls for update DNS-Entries
updateDnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records/${recordId}" # for IPv4 or if provided IPv6
update6DnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records/${recordIdv6}" # if only IPv4 is provided

if [[ $recordIp = "$ipAddr" ]] && [[ $recordIpv6 = "$ip6Addr" ]]; then
    echo "nochg";
    exit 0;
fi

if [[ $recordId = "null" ]]; then
    # Record not exists
	proxy="true" # new Record. Enable proxy by default
    res=$(curl -s -X POST "$createDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"$recordType\",\"name\":\"$hostname\",\"content\":\"$ipAddr\",\"proxied\":$proxy}")
else
    # Record exists
    res=$(curl -s -X PUT "$updateDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"$recordType\",\"name\":\"$hostname\",\"content\":\"$ipAddr\",\"proxied\":$recordProx}")
fi
if [[ $ipv6 = "true" ]] ; then
	if [[ $recordIdv6 = "null" ]]; then
    # IPv6 Record not exists
	proxy="true"; # new entry, enable proxy by default
    res6=$(curl -s -X POST "$createDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"$recType6\",\"name\":\"$hostname\",\"content\":\"$ip6Addr\",\"proxied\":$proxy}");
	else
    # IPv6 Record exists
    res6=$(curl -s -X PUT "$update6DnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"$recType6\",\"name\":\"$hostname\",\"content\":\"$ip6Addr\",\"proxied\":$recordProxv6}");
	fi;
	res6Success=$(echo "$res6" | jq -r ".success");
fi
resSuccess=$(echo "$res" | jq -r ".success")

if [[ $resSuccess = "true" ]] || [[ $res6Success = "true" ]]; then
    echo "good";
else
    echo "badauth";
fi
