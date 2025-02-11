# PPPoE 接口名称
:local pppoeInterface "your-pppoe-interface"

# Cloudflare API Token
:local authToken "your-cloudflare-api-token"

# 服务器配置数组
:local servers {
    {"00:00:00:00:00:01"; "sub1";"example.com"; "Server1"; "your-zone-id1"};
    {"00:00:00:00:00:02"; "sub2";"example.com"; "Server2"; "your-zone-id1"};
    {"00:00:00:00:00:03"; "*"; "example.org"; "Server3"; "your-zone-id2"};
    {"00:00:00:00:00:04"; "@"; "example.org"; "Server4"; "your-zone-id2"}
}

# 确保统一的IPv6地址列表存在
:local unifiedListName "allow ipv6"
:do {
    :local existingList [/ipv6 firewall address-list find where list=$unifiedListName]
    :if ([:len $existingList] = 0) do={
        :log info ("创建统一地址列表: " . $unifiedListName)
        /ipv6 firewall address-list add list=$unifiedListName address="::/0" comment="初始化列表"
    }
    # 删除初始化条目
    /ipv6 firewall address-list remove [find where list=$unifiedListName and address="::/0"]
} on-error={
    :log error ("创建统一地址列表失败")
}

# 服务器配置数组
:local servers {
    {"02:42:c0:a8:59:17"; "mov";"tophedu.org"; "NAS-mov"; "102f492432a879add6dc7c3a04207bd3"};
    {"D0:11:E5:9A:D3:6F"; "mini";"tophedu.org"; "Apple"; "102f492432a879add6dc7c3a04207bd3"};
    {"02:42:c0:a8:59:15"; "*"; "cffq.us.kg"; "NAS-nmp1"; "1a6d14d87f45943a4c1a71040956de23"};
    {"02:42:c0:a8:59:15"; "@"; "cffq.us.kg"; "NAS-nmp2"; "1a6d14d87f45943a4c1a71040956de23"}
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
        :set fullDomain $domain
    } else {
        :if ($subdomain = "*") do={
            :set fullDomain ("*." . $domain)
        } else {
            :set fullDomain ($subdomain . "." . $domain)
        }
    }
    
    # 从邻居表中查找IPv6地址
    :local foundValidIp false
    :local fullIpv6 ""
    :local neighbors [/ipv6 neighbor find where mac-address=$mac]
    
    :foreach neighbor in=$neighbors do={
        :local address [/ipv6 neighbor get $neighbor address]
        :if ([:pick $address 0 1] = "2" || [:pick $address 0 1] = "3") do={
            :do {
                :local pingResult [/ping $address count=2 interval=1]
                :if ([:len $pingResult] > 0) do={
                    :set fullIpv6 $address
                    :set foundValidIp true
                    :log info ("找到可用的IPv6地址: " . $fullIpv6)
                    :break
                }
            } on-error={}
        }
    }
    
    # 如果没有找到有效的IPv6地址，则使用EUI-64生成
    :if (!$foundValidIp) do={
        :log info ("未找到可用的IPv6地址，使用EUI-64生成")
        
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
        :set fullIpv6 ($prefix . ":" . $interfaceId)
    }
    
    :log info ("MAC地址: " . $mac)
    :log info ("完整IPv6地址: " . $fullIpv6)
    
    # 检查单独的服务器地址列表
    :local listName ("allow " . $comment . " server ipv6")
    :local existingList [/ipv6 firewall address-list find where list=$listName]
    
    # 检查统一的IPv6地址列表
    :local unifiedListName "allow ipv6"
    :log info ("检查统一地址列表是否存在: " . $unifiedListName)
    :local existingUnifiedList [/ipv6 firewall address-list find where list=$unifiedListName]
    :log info ("现有统一列表条目数: " . [:len $existingUnifiedList])
    
    # 检查IPv6地址是否已存在于统一列表中
    :local existingIp [/ipv6 firewall address-list find where list=$unifiedListName and address=($fullIpv6 . "/128")]
    :if ([:len $existingIp] = 0) do={
        :log info ("向统一列表添加新地址: " . $fullIpv6)
        /ipv6 firewall address-list add list=$unifiedListName address=($fullIpv6 . "/128") comment=($comment . " - " . $fullDomain)
    } else={
        :log info ("地址已存在于统一列表中，更新注释: " . $fullIpv6)
        :local currentComment [/ipv6 firewall address-list get $existingIp comment]
        :if ([:find $currentComment $comment] < 0) do={
            :local newComment
            :if ([:len $currentComment] > 0) do={
                :local baseComment [:pick $currentComment 0 [:find $currentComment " - "]]
                :if ([:len $baseComment] = 0) do={
                    :set baseComment $currentComment
                }
                :set newComment ($baseComment . " ，" . $comment . " - " . $fullDomain)
            } else={
                :set newComment ($comment . " - " . $fullDomain)
            }
            :log info ("更新地址注释为: " . $newComment)
            /ipv6 firewall address-list set $existingIp comment=$newComment
        }
    }

    # 处理单独的服务器地址列表
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
            :log info ("更新DNS记录: " . $fullDomain)
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
                # 更新统一列表中的地址
                :if ([:len $existingUnifiedEntry] = 0) do={
                    /ipv6 firewall address-list add list=$unifiedListName address=($fullIpv6 . "/128") comment=($comment . " - " . $fullDomain)
                } else={
                    /ipv6 firewall address-list set $existingUnifiedEntry address=($fullIpv6 . "/128")
                }
            }
        }
    }
}

:log info "脚本运行完成"
