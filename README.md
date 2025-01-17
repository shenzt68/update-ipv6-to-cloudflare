# RouterOS IPv6 Cloudflare DDNS 同步脚本

## 功能说明
此脚本用于自动同步 RouterOS 的 IPv6 地址到 Cloudflare DNS，并在本地创建相应的防火墙地址列表。

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
{"MAC后缀"; "二级域名"; "域名"; "备注"; "Zone ID"}
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
    {"xx:xx:xx:xx:xx:17"; "www"; "example.com"; "NAS-1"; "zone-id-1"};
    # 通配符域名
    {"xx:xx:xx:xx:xx:15"; "*"; "example.com"; "NAS-2"; "zone-id-1"};
    # 根域名
    {"xx:xx:xx:xx:xx:15"; "@"; "example.org"; "NAS-3"; "zone-id-2"}
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

### 2. 增强安全性的方法
如果需要更高的安全性，可以：
1. 安装 Cloudflare 根证书
2. 修改脚本启用证书验证
3. 定期更新证书

### 3. 数据安全
- API Token 应妥善保管，避免泄露
- 建议使用最小权限原则配置 API Token
- 定期更换 API Token

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