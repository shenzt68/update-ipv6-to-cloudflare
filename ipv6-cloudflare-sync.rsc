# PPPoE 接口名称
:local pppoeInterface "pppoe-out1"

# Cloudflare API Token，用于认证
:local authToken "your-token-here"

# 服务器配置数组
# 格式：{MAC后缀; 二级域名; 域名; 备注; Zone ID}
# 二级域名：@ 表示根域名，* 表示通配符域名
:local servers {
    {"xx:xx:xx:xx:xx:17"; "www"; "example.com"; "NAS-1"; "zone-id-1"};
    {"xx:xx:xx:xx:xx:15"; "*"; "example.com"; "NAS-2"; "zone-id-1"};
    {"xx:xx:xx:xx:xx:15"; "@"; "example.org"; "NAS-3"; "zone-id-2"}
}

# 获取IPv6前缀
:local prefix
:local dhcpClient [/ipv6 dhcp-client find where interface=$pppoeInterface and status=bound]
:if ([:len $dhcpClient] > 0) do={
    :local ipv6Prefix [/ipv6 dhcp-client get [:pick $dhcpClient 0] prefix]
    :if ([:len $ipv6Prefix] > 0) do={
        :set prefix [:pick $ipv6Prefix 0 ([:find $ipv6Prefix "/" -1])]
        :if ([:pick $prefix ([:len $prefix] - 2)] = "::") do={
            :set prefix [:pick $prefix 0 ([:len $prefix] - 1)]
        }
    } else={
        :return 0
    }
} else={
    :return 0
}

# 确保前缀格式正确
:if ([:pick $prefix ([:len $prefix] - 1)] != ":") do={
    :set prefix ($prefix . ":")
}

# 处理每个服务器
:foreach server in=$servers do={
    :local mac ($server->0)
    :local subdomain ($server->1)
    :local domain ($server->2)
    :local comment ($server->3)
    :local zoneId ($server->4)
    
    # 构建域名
    :local fullDomain
    :if ($subdomain = "@") do={
        # 根域名
        :set fullDomain $domain
    } else {
        :if ($subdomain = "*") do={
            # 通配符域名，使用 *.domain 格式
            :set fullDomain ("*." . $domain)
        } else {
            # 普通二级域名
            :set fullDomain ($subdomain . "." . $domain)
        }
    }
    
    # 生成IPv6地址
    :local macStr $mac
    :local macParts [:toarray $macStr]
    :local interfaceId ""
    
    :foreach part in=$macParts do={
        :if ($part != ":") do={
            :if ([:len $interfaceId] = 0) do={
                :set interfaceId $part
            } else {
                :set interfaceId ($interfaceId . ":" . $part)
            }
        }
    }
    
    # 构建IPv6地址
    :if ([:pick $prefix ([:len $prefix] - 1)] = ":") do={
        :set prefix [:pick $prefix 0 ([:len $prefix] - 1)]
    }
    :if ([:pick $prefix ([:len $prefix] - 1)] = ":") do={
        :set prefix [:pick $prefix 0 ([:len $prefix] - 1)]
    }
    :local fullIpv6 ($prefix . ":" . $interfaceId)
    
    # 检查地址列表
    :local listName ("allow " . $comment . " server ipv6")
    :local existingList [/ipv6 firewall address-list find where list=$listName]
    
    :if ([:len $existingList] = 0) do={
        :local apiUrl "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records"
        :local headers "Authorization: Bearer $authToken,Content-Type: application/json"
        :local data "{\"name\":\"$fullDomain\",\"type\":\"AAAA\",\"content\":\"$fullIpv6\",\"proxied\":false}"
        :local success false
        
        :do {
            /tool fetch url=$apiUrl \
                http-method=post \
                http-header-field=$headers \
                http-data=$data \
                check-certificate=no \
                output=none
            :set success true
        } on-error={
            :delay 5s
        }
        
        # 只有在 API 调用成功后才创建本地地址列表
        :if ($success) do={
            /ipv6 firewall address-list add list=$listName address=$fullIpv6 comment=$fullDomain
        }
        
    } else={
        # 获取当前列表中的地址，并移除CIDR前缀（如果有）
        :local currentIp [/ipv6 firewall address-list get [find list=$listName] address]
        :if ([:find $currentIp "/"] > 0) do={
            :set currentIp [:pick $currentIp 0 [:find $currentIp "/"]]
        }
        
        # 比较IPv6地址，检查前缀和完整地址
        :local currentPrefix [:pick $currentIp 0 19]
        :local newPrefix [:pick $fullIpv6 0 19]
        
        :log info "检查服务器: $comment"
        :log info "当前地址: $currentIp"
        :log info "新地址: $fullIpv6"

        
        :if ($currentPrefix != $newPrefix || $currentIp != $fullIpv6) do={
            :log info "需要更新DNS记录"
            :local success false
            
            # 直接更新 DNS 记录
            :do {
                # 为每个域名指定固定的记录ID
                :local recordId
                :if ($fullDomain = "dsmt.tophedu.org") do={
                    :set recordId "9e52dd694a24a1c8c7deb0a5bf5830be"
                }
                :if ($fullDomain = "*.kqkq.us.kg") do={
                    :set recordId "cd63dff2b5b2cfa2d66cefadafe4f918"
                }
                
                :if ([:len $recordId] > 0) do={
                    :local updateUrl "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records/$recordId"
                    :local headers "Authorization: Bearer $authToken,Content-Type: application/json"
                    :local data "{\"name\":\"$fullDomain\",\"type\":\"AAAA\",\"content\":\"$fullIpv6\",\"proxied\":false}"
                    
                    :log info "更新DNS记录: $updateUrl"
                    :log info "更新数据: $data"
                    
                    :do {
                        /tool fetch url=$updateUrl http-method=put http-header-field=$headers http-data=$data check-certificate=no output=none
                        :set success true
                        :log info "DNS记录更新成功"
                    } on-error={
                        :log error "DNS记录更新失败"
                        :delay 5s
                    }
                }
            } on-error={
                :log error "DNS更新失败"
                :delay 5s
            }
            
            # 只有在DNS更新成功后才更新本地地址列表
            :if ($success) do={
                :log info "更新本地地址列表"
                /ipv6 firewall address-list set [find list=$listName] address=($fullIpv6 . "/128")
                :log info "本地地址列表更新成功"
            }
        } else {
            :log info "地址未变化，无需更新"
        }
    }
}

:log info "脚本运行结束"