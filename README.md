# RouterOS IPv6 Cloudflare DDNS 同步脚本

## 功能说明
这个脚本用于自动更新 RouterOS 设备上的 IPv6 地址到 Cloudflare DNS 记录。脚本会自动生成基于 MAC 地址的 IPv6 地址（使用 EUI-64 格式），并将其更新到 Cloudflare DNS 记录中。同时，脚本也会在本地防火墙地址列表中维护这些 IPv6 地址。

## 使用说明

### 1. 文件说明
- `ipv6-cloudflare-sync.rsc`: 主脚本文件
- `install-cloudflare-cert.rsc`: Cloudflare 证书安装脚本（可选）

### 2. 准备工作
1. 获取 Cloudflare API Token
2. 获取需要更新的域名的 Zone ID
3. 准备好需要更新的域名和对应的 MAC 地址后缀
4. 确认 PPPoE 接口名称

### 3. 基础配置
在脚本开头配置以下变量：
```routeros
# PPPoE 接口名称
:local pppoeInterface "pppoe-out1"

# Cloudflare API Token
:local authToken "your-token-here"
```

### 4. 服务器配置数组
在脚本中配置 `servers` 数组，每个条目包含 5 个参数：
```routeros
{"MAC地址"; "二级域名"; "域名"; "备注"; "Zone ID"}
```

参数说明：
- MAC后缀：用于生成 IPv6 地址的接口标识符
- 二级域名：
  - 使用 "@" 表示根域名（如 example.com）
  - 使用 "*" 表示通配符域名（如 *.example.com）
  - 使用具体名称表示二级域名（如 www.example.com）
- 域名：完整的域名
- 备注：用于生成防火墙地址列表名称
- Zone ID：Cloudflare 的区域 ID

### 5. 配置示例
```routeros
:local servers {
    # 普通二级域名
     {"00:11:22:33:44:55"; "www"; "example.com"; "Web-Server"; "your-zone-id-1"};
    # 通配符域名
    {"aa:bb:cc:dd:ee:ff"; "@"; "example.org"; "Mail-Server"; "your-zone-id-2"};
    # 根域名
    {"11:22:33:44:55:66"; "*"; "example.net"; "Wildcard-Server"; "your-zone-id-3"}
}
```

### 6. 安装步骤
1. 上传脚本到 RouterOS：
```routeros
/system script add name=ipv6-cloudflare-sync source=[/file get ipv6-cloudflare-sync.rsc contents]
```

2. 修改脚本中的配置：
   - 更新 `pppoeInterface` 为你的 PPPoE 接口名称
   - 更新 `authToken` 为你的 Cloudflare API Token
   - 配置 `servers` 数组

3. 设置定时运行：
```routeros
/system scheduler add name=ipv6-sync interval=5m on-event="/system script run ipv6-cloudflare-sync"
```

### 7. 运行方式
- 手动运行：`/system script run ipv6-cloudflare-sync`
- 自动运行：通过 scheduler 每 5 分钟运行一次

## 安全说明

### 1. SSL 证书验证
当前脚本使用 `check-certificate=no` 禁用了 SSL 证书验证，这可能带来以下安全风险：
- 可能受到中间人攻击(MITM)
- 无法验证 Cloudflare API 服务器的身份

## 安全性说明

### SSL 证书验证
1. 当前脚本使用 `check-certificate=no` 禁用了 SSL 证书验证，这是为了避免证书相关的问题
2. 这种设置可能带来安全风险：
   - 可能受到中间人攻击(MITM)
   - 无法验证 Cloudflare API 服务器的身份

### 增强安全性的方法
如果需要更高的安全性，可以：
1. 安装 Cloudflare 根证书：
   ```routeros
   # 使用 install-cloudflare-cert.rsc 脚本安装证书
   /system script run install-cloudflare-cert
   ```

2. 修改脚本中的 API 调用，启用证书验证：
   - 移除所有 `check-certificate=no` 参数
   - 添加 `certificate=cloudflare_ca` 参数

3. 定期更新证书

### 使用建议
1. 在内部网络环境中，使用当前的 `check-certificate=no` 设置是可接受的
2. 如果路由器直接暴露在公网，建议启用证书验证
3. 无论是否启用证书验证，都要确保 API Token 的安全性

## 免责声明

1. 使用说明
- 本脚本仅供学习和参考使用
- 使用前请仔细阅读脚本内容和配置说明
- 使用者应对脚本的运行结果负责

2. 安全性
- 脚本默认禁用 SSL 证书验证，使用者需自行评估安全风险
- 不建议在关键业务环境中使用未经安全加固的版本

3. 责任限制
- 作者不对因使用本脚本造成的任何直接或间接损失负责
- 包括但不限于：数据丢失、服务中断、安全漏洞等

4. 使用条款
- 可自由修改和分发本脚本
- 使用本脚本即表示同意本免责声明的所有条款

## 更新记录
- 2024-01-17：初始版本 
