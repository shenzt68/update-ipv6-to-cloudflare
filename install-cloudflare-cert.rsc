# 下载并安装 Cloudflare 根证书
:do {
    /tool fetch url="https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem" dst-path=cloudflare_ca.pem
    :delay 2s
    /certificate import file-name=cloudflare_ca.pem passphrase=""
    :delay 2s
    /file remove cloudflare_ca.pem
    :log info "Cloudflare 证书安装成功"
} on-error={
    :log error "Cloudflare 证书安装失败"
} 