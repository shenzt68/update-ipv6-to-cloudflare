# PPPoE 接口名称
:local pppoeInterface "pppoe-out1"

# Cloudflare API Token
# 用于认证Cloudflare API请求，可以在Cloudflare面板 -> My Profile -> API Tokens中创建
:local authToken "你的API Token"

# 服务器配置数组
# 数组格式：{"MAC地址"; "子域名"; "域名"; "备注"; "Zone ID"}
# MAC地址：服务器的MAC地址
# 子域名：@ 表示根域名，* 表示通配符域名，其他为具体子域名
# 域名：Cloudflare上的域名
# 备注：用于防火墙地址列表的备注
# Zone ID：域名对应的Cloudflare Zone ID
:local servers {
    {"00:11:22:33:44:55"; "www"; "example.com"; "Web-Server"; "your-zone-id-1"};
    {"aa:bb:cc:dd:ee:ff"; "@"; "example.org"; "Mail-Server"; "your-zone-id-2"};
    {"11:22:33:44:55:66"; "*"; "example.net"; "Wildcard-Server"; "your-zone-id-3"}
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
    :local macStr ""
    :local currentChar ""
    :for i from=0 to=([:len $mac]-1) do={
        :set currentChar [:pick $mac $i]
        :if ($currentChar != ":") do={
            :set macStr ($macStr . $currentChar)
        }
    }
    
    # 分割MAC地址为前24位和后24位
    :local firstPart [:pick $macStr 0 6]
    :local secondPart [:pick $macStr 6 12]
    
    # 修改第7位（U/L位）
    :local firstByte [:pick $firstPart 0 2]
    :local firstByteNum [:tonum ("0x" . $firstByte)]
    :set firstByteNum ($firstByteNum ^ 2)
    :local hexChars "0123456789abcdef"
    :local newFirstByte ([:pick $hexChars (($firstByteNum >> 4) & 15)] . [:pick $hexChars ($firstByteNum & 15)])
    
    # 构建完整的EUI-64标识符
    :local modifiedFirst ($newFirstByte . [:pick $firstPart 2 6])
    :local eui64 ($modifiedFirst . "fffe" . $secondPart)
    
    # 按照标准IPv6格式分组
    :local group1 [:pick $eui64 0 4]
    :local group2 [:pick $eui64 4 8]
    :local group3 [:pick $eui64 8 12]
    :local group4 [:pick $eui64 12 16]
    
    # 去掉第一组前导零
    :while ([:len $group1] > 1 && [:pick $group1 0] = "0") do={
        :set group1 [:pick $group1 1 [:len $group1]]
    }
    
    # 组合成标准格式的接口ID
    :local interfaceId ($group1 . ":" . $group2 . ":" . $group3 . ":" . $group4)
    
    # 生成完整的IPv6地址
    :if ([:pick $prefix ([:len $prefix] - 1)] = ":") do={
        :set prefix [:pick $prefix 0 ([:len $prefix] - 1)]
    }
    # 检查并修复前缀中的双冒号
    :if ([:find $prefix "::"] > 0) do={
        :set prefix [:pick $prefix 0 [:find $prefix "::"]]
    }
    # 确保前缀不以冒号结尾
    :while ([:pick $prefix ([:len $prefix] - 1)] = ":") do={
        :set prefix [:pick $prefix 0 ([:len $prefix] - 1)]
    }
    :local fullIpv6 ($prefix . ":" . $interfaceId)
    
    :log info ("MAC地址: " . $mac)
    :log info ("接口ID: " . $interfaceId)
    :log info ("完整IPv6地址: " . $fullIpv6)
    
    # 检查地址列表
    :local listName ("allow " . $comment . " server ipv6")
    :local existingList [/ipv6 firewall address-list find where list=$listName]
    
    :if ([:len $existingList] = 0) do={
        :local apiUrl "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records"
        :local headers "Authorization: Bearer $authToken,Content-Type: application/json"
        :local data "{\"name\":\"$fullDomain\",\"type\":\"AAAA\",\"content\":\"$fullIpv6\",\"proxied\":false}"
        :local success false
        
        # 首先检查记录是否存在
        :do {
            :local checkUrl ($apiUrl . "?type=AAAA&name=$fullDomain")
            :local fetchResult [/tool fetch url=$checkUrl http-header-field="Authorization: Bearer $authToken" check-certificate=no output=user as-value]
            
            :if ($fetchResult->"status" = "finished") do={
                :local content ($fetchResult->"data")
                :local recordId ""
                :local startPos [:find $content "\"id\":\"" -1]
                
                :if ($startPos > 0) do={
                    # 记录已存在，执行更新操作
                    :set startPos ($startPos + 6)
                    :local endPos [:find $content "\"" $startPos]
                    :set recordId [:pick $content $startPos $endPos]
                    
                    :local updateUrl ($apiUrl . "/" . $recordId)
                    /tool fetch url=$updateUrl \
                        http-method=put \
                        http-header-field=$headers \
                        http-data=$data \
                        check-certificate=no \
                        output=none
                } else={
                    # 记录不存在，创建新记录
                    /tool fetch url=$apiUrl \
                        http-method=post \
                        http-header-field=$headers \
                        http-data=$data \
                        check-certificate=no \
                        output=none
                }
                :set success true
            }
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
        # 处理空地址或双冒号结尾的地址
        :if ([:pick $currentIp ([:len $currentIp] - 2)] = "::") do={
            :set currentIp ""
        }
        
        # 比较IPv6地址，检查前缀和完整地址
        :local currentPrefix ""
        :if ([:len $currentIp] > 0) do={
            :set currentPrefix [:pick $currentIp 0 19]
        }
        :local newPrefix [:pick $fullIpv6 0 19]
        
        :log info "检查服务器: $comment"
        :log info "当前地址: $currentIp"
        :log info "新地址: $fullIpv6"

        :if ([:len $currentIp] = 0 || $currentPrefix != $newPrefix || $currentIp != $fullIpv6) do={
            :log info "需要更新DNS记录"
            :local success false
            
            # 先获取并更新 DNS 记录
            :do {
                :local dnsApiUrl "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records?type=AAAA&name=$fullDomain"
                :local fetchResult [/tool fetch url=$dnsApiUrl http-header-field="Authorization: Bearer $authToken" check-certificate=no output=user as-value]
                
                :if ($fetchResult->"status" = "finished") do={
                    :local content ($fetchResult->"data")
                    :local recordId ""
                    :local startPos [:find $content "\"id\":\"" -1]
                    
                    :if ($startPos > 0) do={
                        :set startPos ($startPos + 6)
                        :local endPos [:find $content "\"" $startPos]
                        :set recordId [:pick $content $startPos $endPos]
                        
                        :if ([:len $recordId] > 0) do={
                            # 更新现有记录
                            :local updateUrl "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records/$recordId"
                            :local headers "Authorization: Bearer $authToken,Content-Type: application/json"
                            :local data "{\"name\":\"$fullDomain\",\"type\":\"AAAA\",\"content\":\"$fullIpv6\",\"proxied\":false}"
                            
                            /tool fetch url=$updateUrl http-method=put http-header-field=$headers http-data=$data check-certificate=no output=none
                            :set success true
                        }
                    }
                }
            } on-error={
                :delay 1s
            }
            
            # 只有在DNS更新成功后才更新本地地址列表
            :if ($success) do={
                /ipv6 firewall address-list set [find list=$listName] address=($fullIpv6 . "/128")
            }
        } else {
            :log info "地址未变化，无需更新"
        }
    }
}

:log info "脚本运行结束"
