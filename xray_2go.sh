#!/bin/bash

# 定义颜色
re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
skybule="\e[1;36m"
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
skyblue() { echo -e "\e[1;36m$1\033[0m"; }
reading() { read -p "$(red "$1")" "$2"; }

# 定义常量
server_name="xray"
work_dir="/etc/xray"
config_dir="${work_dir}/config.json"
client_dir="${work_dir}/url.txt"
# 定义环境变量
export UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
export CADDY_PORT=${CADDY_PORT:-$(shuf -i 1000-60000 -n 1)}
export ARGO_DOMAIN=${ARGO_DOMAIN:-''}   
export ARGO_AUTH=${ARGO_AUTH:-''} 
export CFIP=${CFIP:-'aliyun.2096.us.kg'} 
export CFPORT=${CFPORT:-'2096'}   
export ARGO_PORT=${ARGO_PORT:-'8080'}

# 检查是否为root下运行
[[ $EUID -ne 0 ]] && red "请在root用户下运行脚本" && exit 1

# 检查 xray 是否已安装
check_xray() {
if [ -f "${work_dir}/${server_name}" ]; then
    if [ -f /etc/alpine-release ]; then
        rc-service xray status | grep -q "started" && green "running" && return 0 || yellow "not running" && return 1
    else 
        [ "$(systemctl is-active xray)" = "active" ] && green "running" && return 0 || yellow "not running" && return 1
    fi
else
    red "not installed"
    return 2
fi
}

# 检查 argo 是否已安装
check_argo() {
if [ -f "${work_dir}/argo" ]; then
    if [ -f /etc/alpine-release ]; then
        rc-service tunnel status | grep -q "started" && green "running" && return 0 || yellow "not running" && return 1
    else 
        [ "$(systemctl is-active tunnel)" = "active" ] && green "running" && return 0 || yellow "not running" && return 1
    fi
else
    red "not installed"
    return 2
fi
}

# 检查 caddy 是否已安装
check_caddy() {
if command -v caddy &>/dev/null; then
    if [ -f /etc/alpine-release ]; then
        rc-service caddy status | grep -q "started" && green "running" && return 0 || yellow "not running" && return 1
    else 
        [ "$(systemctl is-active caddy)" = "active" ] && green "running" && return 0 || yellow "not running" && return 1
    fi
else
    red "not installed"
    return 2
fi
}

#根据系统类型安装、卸载依赖
manage_packages() {
    if [ $# -lt 2 ]; then
        red "Unspecified package name or action" 
        return 1
    fi

    action=$1
    shift

    for package in "$@"; do
        if [ "$action" == "install" ]; then
            if command -v "$package" &>/dev/null; then
                green "${package} already installed"
                continue
            fi
            yellow "正在安装 ${package}..."
            if command -v apt &>/dev/null; then
                apt install -y "$package"
            elif command -v dnf &>/dev/null; then
                dnf install -y "$package"
            elif command -v yum &>/dev/null; then
                yum install -y "$package"
            elif command -v apk &>/dev/null; then
                apk update
                apk add "$package"
            else
                red "Unknown system!"
                return 1
            fi
        elif [ "$action" == "uninstall" ]; then
            if ! command -v "$package" &>/dev/null; then
                yellow "${package} is not installed"
                continue
            fi
            yellow "正在卸载 ${package}..."
            if command -v apt &>/dev/null; then
                apt remove -y "$package" && apt autoremove -y
            elif command -v dnf &>/dev/null; then
                dnf remove -y "$package" && dnf autoremove -y
            elif command -v yum &>/dev/null; then
                yum remove -y "$package" && yum autoremove -y
            elif command -v apk &>/dev/null; then
                apk del "$package"
            else
                red "Unknown system!"
                return 1
            fi
        else
            red "Unknown action: $action"
            return 1
        fi
    done

    return 0
}

# 获取ip
get_realip() {
  ip=$(curl -s --max-time 2 ipv4.ip.sb)
  if [ -z "$ip" ]; then
      ipv6=$(curl -s --max-time 2 ipv6.ip.sb)
      echo "[$ipv6]"
  else
      if echo "$(curl -s http://ipinfo.io/org)" | grep -qE 'Cloudflare|UnReal|AEZA|Andrei'; then
          ipv6=$(curl -s --max-time 2 ipv6.ip.sb)
          echo "[$ipv6]"
      else
          echo "$ip"
      fi
  fi
}

# 下载并安装 xray,cloudflared
install_xray() {
    clear
    purple "正在安装Xray-2go中，请稍等..."
    ARCH_RAW=$(uname -m)
    case "${ARCH_RAW}" in
        'x86_64') ARCH='amd64'; ARCH_ARG='64' ;;
        'x86' | 'i686' | 'i386') ARCH='386'; ARCH_ARG='32' ;;
        'aarch64' | 'arm64') ARCH='arm64'; ARCH_ARG='arm64-v8a' ;;
        'armv7l') ARCH='armv7'; ARCH_ARG='arm32-v7a' ;;
        's390x') ARCH='s390x' ;;
        *) red "不支持的架构: ${ARCH_RAW}"; exit 1 ;;
    esac

    # 下载sing-box,cloudflared
    [ ! -d "${work_dir}" ] && mkdir -p "${work_dir}" && chmod 777 "${work_dir}"
    curl -sLo "${work_dir}/${server_name}.zip" "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip"
    curl -sLo "${work_dir}/qrencode" "https://github.com/eooce/test/releases/download/${ARCH}/qrencode-linux-${ARCH}"
    curl -sLo "${work_dir}/argo" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}"
    unzip "${work_dir}/${server_name}.zip" -d "${work_dir}/" > /dev/null 2>&1 && chmod +x ${work_dir}/${server_name} ${work_dir}/argo ${work_dir}/qrencode
    rm -rf "${work_dir}/${server_name}.zip" "${work_dir}/geosite.dat" "${work_dir}/geoip.dat" "${work_dir}/README.md" "${work_dir}/LICENSE" 

   # 生成随机UUID和密码
    password=$(< /dev/urandom tr -dc 'A-Za-z0-9' | head -c 24)
    GRPC_PORT=$((CADDY_PORT + 1))

    # 关闭防火墙
    iptables -A INPUT -p tcp --dport 8080 -j ACCEPT > /dev/null 2>&1
    iptables -A INPUT -p tcp --dport $GRPC_PORT -j ACCEPT > /dev/null 2>&1
    iptables -P FORWARD ACCEPT > /dev/null 2>&1 
    iptables -P OUTPUT ACCEPT > /dev/null 2>&1
    iptables -F > /dev/null 2>&1
    manage_packages uninstall ufw firewalld iptables-persistent iptables-services > /dev/null 2>&1

    output=$(/etc/xray/xray x25519)
    private_key=$(echo "$output" | grep "Private key" | awk '{print $3}')
    public_key=$(echo "$output" | grep "Public key" | awk '{print $3}')

   # 生成配置文件
cat > "${config_dir}" << EOF
{
  "log": { "access": "/dev/null", "error": "/dev/null", "loglevel": "none" },
  "inbounds": [
    {
      "port": $ARGO_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID", "flow": "xtls-rprx-vision" }],
        "decryption": "none",
        "fallbacks": [
          { "dest": 3001 }, { "path": "/vless", "dest": 3002 },
          { "path": "/vmess", "dest": 3003 }, { "path": "", "dest": 3004 }
        ]
      },
      "streamSettings": { "network": "tcp" }
    },
    {
      "port": 3001, "listen": "127.0.0.1", "protocol": "vless",
      "settings": { "clients": [{ "id": "$UUID" }], "decryption": "none" },
      "streamSettings": { "network": "ws", "security": "none" }
    },
    {
      "port": 3002, "listen": "127.0.0.1", "protocol": "vless",
      "settings": { "clients": [{ "id": "$UUID", "level": 0 }], "decryption": "none" },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "/vless" } },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"], "metadataOnly": false }
    },
    {
      "port": 3003, "listen": "127.0.0.1", "protocol": "vmess",
      "settings": { "clients": [{ "id": "$UUID", "alterId": 0 }] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" } },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"], "metadataOnly": false }
    },
    {
      "port": 3004, "listen": "127.0.0.1", "protocol": "vmess",
      "settings": {"clients": [{"id": "$UUID", "alterId": 0, "security": "auto"}]},
      "streamSettings": {"network": "splithttp", "security": "none", "httpSettings": {"host": "", "path": ""}},
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"], "metadataOnly": false}
    },
    {
      "listen":"0.0.0.0","port":$GRPC_PORT,"protocol":"vless","settings":{"clients":[{"id":"$UUID"}],"decryption":"none"},"streamSettings":{"network":"grpc","security":"reality","realitySettings":{"dest":"www.iij.ad.jp:443","serverNames":["www.iij.ad.jp"],"privateKey":"$private_key","shortIds":[""]},"grpcSettings":{"serviceName":"grpc"}},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"]}}
  ],
  "dns": { "servers": ["https+local://8.8.8.8/dns-query"] },
  "outbounds": [
    { "protocol": "freedom" },
    {
      "tag": "WARP", "protocol": "wireguard",
      "settings": {
        "secretKey": "YFYOAdbw1bKTHlNNi+aEjBM3BO7unuFC5rOkMRAz9XY=",
        "address": ["172.16.0.2/32", "2606:4700:110:8a36:df92:102a:9602:fa18/128"],
        "peers": [{ "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=", "allowedIPs": ["0.0.0.0/0", "::/0"], "endpoint": "162.159.193.10:2408" }],
        "reserved": [78, 135, 76], "mtu": 1280
      }
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [{ "type": "field", "domain": ["domain:openai.com", "domain:ai.com", "domain:chat.openai.com", "domain:chatgpt.com"], "outboundTag": "WARP" }]
  }
}
EOF
}
# debian/ubuntu/centos 守护进程
main_systemd_services() {
    cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
NoNewPrivileges=yes
ExecStart=$work_dir/xray run -c $config_dir
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/tunnel.service << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=/etc/xray/argo tunnel --url http://localhost:$ARGO_PORT --no-autoupdate --edge-ip-version auto --protocol http2
StandardOutput=append:/etc/xray/argo.log
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target

EOF
    if [ -f /etc/centos-release ]; then
        yum install -y chrony
        systemctl start chronyd
        systemctl enable chronyd
        chronyc -a makestep
        yum update -y ca-certificates
        bash -c 'echo "0 0" > /proc/sys/net/ipv4/ping_group_range'
    fi
    bash -c 'echo "0 0" > /proc/sys/net/ipv4/ping_group_range'
    systemctl daemon-reload
    systemctl enable xray
    systemctl start xray
    systemctl enable tunnel
    systemctl start tunnel
}
# 适配alpine 守护进程
alpine_openrc_services() {
    cat > /etc/init.d/xray << 'EOF'
#!/sbin/openrc-run

description="Xray service"
command="/etc/xray/xray"
command_args="run -c /etc/xray/config.json"
command_background=true
pidfile="/var/run/xray.pid"
EOF

    cat > /etc/init.d/tunnel << 'EOF'
#!/sbin/openrc-run

description="Cloudflare Tunnel"
command="/bin/sh"
command_args="-c '/etc/xray/argo tunnel --url http://localhost:8080 --no-autoupdate --edge-ip-version auto --protocol http2 > /etc/xray/argo.log 2>&1'"
command_background=true
pidfile="/var/run/tunnel.pid"
EOF

    chmod +x /etc/init.d/xray
    chmod +x /etc/init.d/tunnel

    rc-update add xray default
    rc-update add tunnel default

}


get_info() {  
  clear
  IP=$(get_realip)

  isp=$(curl -s --max-time 2 https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g' || echo "vps")

  argodomain=$(grep -oE 'https://[[:alnum:]+\.-]+\.trycloudflare\.com' /etc/xray/argo.log | sed 's@https://@@')

  echo -e "${green}\nArgoDomain：${re}${purple}$argodomain${re}"

  yellow "\n温馨提醒：NAT机需将订阅端口更改为可用端口范围内的端口,否则无法订阅\n"

  cat > ${work_dir}/url.txt <<EOF
vless://${UUID}@${IP}:${GRPC_PORT}??encryption=none&security=reality&sni=www.iij.ad.jp&fp=chrome&pbk=${public_key}&allowInsecure=1&type=grpc&authority=www.iij.ad.jp&serviceName=grpc&mode=gun#${isp}

vless://${UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&sni=${argodomain}&type=ws&host=${argodomain}&path=%2Fvless%3Fed%3D2048#${isp}

vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${isp}\", \"add\": \"${CFIP}\", \"port\": \"${CFPORT}\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${argodomain}\", \"path\": \"/vmess?ed=2048\", \"tls\": \"tls\", \"sni\": \"${argodomain}\", \"alpn\": \"\" }" | base64 -w0)

vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${isp}\", \"add\": \"${CFIP}\", \"port\": \"${CFPORT}\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"splithttp\", \"type\": \"none\", \"host\": \"${argodomain}\", \"path\": \"\", \"tls\": \"tls\", \"sni\": \"${argodomain}\", \"alpn\": \"\" }" | base64 -w0)
EOF
echo ""
while IFS= read -r line; do echo -e "${purple}$line"; done < ${work_dir}/url.txt
base64 -w0 ${work_dir}/url.txt > ${work_dir}/sub.txt
green "\n节点订阅链接：http://$IP:$CADDY_PORT/$password\n\n订阅链接适用于V2rayN,Nekbox,karing,Sterisand,Loon,小火箭,圈X等\n"
$work_dir/qrencode "http://$IP:$CADDY_PORT/$password"
echo ""
}


# caddy订阅配置
add_caddy_conf() {
[ -f /etc/caddy/Caddyfile ] && cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak
rm -rf /etc/caddy/Caddyfile
    cat > /etc/caddy/Caddyfile << EOF
{
    auto_https off
    log {
        output file /var/log/caddy/caddy.log {
            roll_size 10MB
            roll_keep 10
            roll_keep_for 720h
        }
    }
}

:$CADDY_PORT {
    handle /$password {
        root * /etc/xray
        try_files /sub.txt
        file_server browse
        header Content-Type "text/plain; charset=utf-8"
    }

    handle {
        respond "404 Not Found" 404
    }
}
EOF

/usr/bin/caddy validate --config /etc/caddy/Caddyfile > /dev/null 2>&1

if [ $? -eq 0 ]; then
    if [ -f /etc/alpine-release ]; then
        rc-service caddy restart
    else
        systemctl daemon-reload
        systemctl restart caddy
    fi
else
    red "Caddy 配置文件验证失败，请检查配置。\nissues 反馈：https://github.com/eooce/xray-argo/issues\n"
fi
}


# 启动 xray
start_xray() {
if [ ${check_xray} -eq 1 ]; then
    yellow "\n正在启动 ${server_name} 服务\n" 
    if [ -f /etc/alpine-release ]; then
        rc-service xray start
    else
        systemctl daemon-reload
        systemctl start "${server_name}"
    fi
   if [ $? -eq 0 ]; then
       green "${server_name} 服务已成功启动\n"
   else
       red "${server_name} 服务启动失败\n"
   fi
elif [ ${check_xray} -eq 0 ]; then
    yellow "xray 正在运行\n"
    sleep 1
    menu
else
    yellow "xray 尚未安装!\n"
    sleep 1
    menu
fi
}

# 停止 xray
stop_xray() {
if [ ${check_xray} -eq 0 ]; then
   yellow "\n正在停止 ${server_name} 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service xray stop
    else
        systemctl stop "${server_name}"
    fi
   if [ $? -eq 0 ]; then
       green "${server_name} 服务已成功停止\n"
   else
       red "${server_name} 服务停止失败\n"
   fi

elif [ ${check_xray} -eq 1 ]; then
    yellow "xray 未运行\n"
    sleep 1
    menu
else
    yellow "xray 尚未安装！\n"
    sleep 1
    menu
fi
}

# 重启 xray
restart_xray() {
if [ ${check_xray} -eq 0 ]; then
   yellow "\n正在重启 ${server_name} 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service ${server_name} restart
    else
        systemctl daemon-reload
        systemctl restart "${server_name}"
    fi
    if [ $? -eq 0 ]; then
        green "${server_name} 服务已成功重启\n"
    else
        red "${server_name} 服务重启失败\n"
    fi
elif [ ${check_xray} -eq 1 ]; then
    yellow "xray 未运行\n"
    sleep 1
    menu
else
    yellow "xray 尚未安装！\n"
    sleep 1
    menu
fi
}

# 启动 argo
start_argo() {
if [ ${check_argo} -eq 1 ]; then
    yellow "\n正在启动 Argo 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service tunnel start
    else
        systemctl daemon-reload
        systemctl start tunnel
    fi
    if [ $? -eq 0 ]; then
        green "Argo 服务已成功重启\n"
    else
        red "Argo 服务重启失败\n"
    fi
elif [ ${check_argo} -eq 0 ]; then
    green "Argo 服务正在运行\n"
    sleep 1
    menu
else
    yellow "Argo 尚未安装！\n"
    sleep 1
    menu
fi
}

# 停止 argo
stop_argo() {
if [ ${check_argo} -eq 0 ]; then
    yellow "\n正在停止 Argo 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service stop start
    else
        systemctl daemon-reload
        systemctl stop tunnel
    fi
    if [ $? -eq 0 ]; then
        green "Argo 服务已成功停止\n"
    else
        red "Argo 服务停止失败\n"
    fi
elif [ ${check_argo} -eq 1 ]; then
    yellow "Argo 服务未运行\n"
    sleep 1
    menu
else
    yellow "Argo 尚未安装！\n"
    sleep 1
    menu
fi
}

# 重启 argo
restart_argo() {
if [ ${check_argo} -eq 0 ]; then
    yellow "\n正在重启 Argo 服务\n"
    rm /etc/xray/argo.log
    if [ -f /etc/alpine-release ]; then
        rc-service tunnel restart
    else
        systemctl daemon-reload
        systemctl restart tunnel
    fi
    if [ $? -eq 0 ]; then
        green "Argo 服务已成功重启\n"
    else
        red "Argo 服务重启失败\n"
    fi
elif [ ${check_argo} -eq 1 ]; then
    yellow "Argo 服务未运行\n"
    sleep 1
    menu
else
    yellow "Argo 尚未安装！\n"
    sleep 1
    menu
fi
}

# 启动 caddy
start_caddy() {
if command -v caddy &>/dev/null; then
    yellow "\n正在启动 caddy 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service caddy start
    else
        systemctl daemon-reload
        systemctl start caddy
    fi
    if [ $? -eq 0 ]; then
        green "caddy 服务已成功启动\n"
    else
        red "caddy 启动失败\n"
    fi
else
    yellow "caddy 尚未安装！\n"
    sleep 1
    menu
fi
}

# 重启 caddy
restart_caddy() {
if command -v caddy &>/dev/null; then
    yellow "\n正在重启 caddy 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service caddy restart
    else
        systemctl restart caddy
    fi
    if [ $? -eq 0 ]; then
        green "caddy 服务已成功重启\n"
    else
        red "caddy 重启失败\n"
    fi
else
    yellow "caddy 尚未安装！\n"
    sleep 1
    menu
fi
}

# 卸载 xray
uninstall_xray() {
   reading "确定要卸载 xray 吗? (y/n): " choice
   case "${choice}" in
       y|Y)
           yellow "正在卸载 xray"
           if [ -f /etc/alpine-release ]; then
                rc-service xray stop
                rc-service tunnel stop
                rm /etc/init.d/xray /etc/init.d/tunnel
                rc-update del xray default
                rc-update del tunnel default
           else
                # 停止 xray和 argo 服务
                systemctl stop "${server_name}"
                systemctl stop tunnel
                # 禁用 xray 服务
                systemctl disable "${server_name}"
                systemctl disable tunnel

                # 重新加载 systemd
                systemctl daemon-reload || true
            fi
           # 删除配置文件和日志
           rm -rf "${work_dir}" || true
           
           # 卸载caddy
           reading "\n是否卸载 caddy？${green}(卸载请输入 ${yellow}y${re} ${green}回车将跳过卸载caddy) (y/n): ${re}" choice
            case "${choice}" in
                y|Y)
                    manage_packages uninstall caddy
                    ;;
                 *)
                    yellow "取消卸载caddy\n"
                    ;;
            esac

            green "\nXray_2go 卸载成功\n"
           ;;
       *)
           purple "已取消卸载操作\n"
           ;;
   esac
}

# 创建快捷指令
create_shortcut() {
  cat > "$work_dir/2go.sh" << EOF
#!/usr/bin/env bash

bash <(curl -Ls https://github.com/eooce/xray-2go/raw/main/xray_2go.sh) \$1
EOF
  chmod +x "$work_dir/2go.sh"
  ln -sf "$work_dir/2go.sh" /usr/bin/2go
  if [ -s /usr/bin/2go ]; then
    green "\n2go 快捷指令创建成功\n"
  else
    red "\n2go 快捷指令创建失败\n"
  fi
}

# 适配alpine运行argo报错用户组和dns的问题
change_hosts() {
    sh -c 'echo "0 0" > /proc/sys/net/ipv4/ping_group_range'
    sed -i '1s/.*/127.0.0.1   localhost/' /etc/hosts
    sed -i '2s/.*/::1         localhost/' /etc/hosts
}

# 变更配置
change_config() {
clear
echo ""
green "1. 修改端口"
skyblue "------------"
green "2. 修改UUID"
skyblue "------------"
green "3. 修改Reality伪装域名"
skyblue "------------"
purple "${purple}4. 返回主菜单"
skyblue "------------"
reading "请输入选择: " choice
case "${choice}" in
    1)
        echo ""
        green "1. 修改ARGO端口"
        skyblue "------------"
        green "2. 修改grpc-reality端口"
        skyblue "------------"
        purple "3. 返回上一级菜单"
        skyblue "------------"
        reading "请输入选择: " choice
        case "${choice}" in
            1)  
                reading "\n请输入ARGO端口 (回车跳过将使用随机端口): " argo_port
                [ -z "$argo_port" ] && argo_port=$(shuf -i 8000-9000 -n 1)
                green "你的ARGO端口为：$argo_port"
                sed -i "5s/[0-9]\{1,5\}/$argo_port/" /etc/xray/config.json
                if [ -e "/etc/xray/tunnel.yml" ]; then
                    sed -i 's|\(service: http://localhost:\)[0-9]\{1,5\}|\1'"$argo_port"'|' /etc/xray/tunnel.yml
                else
                    if grep -q '--url http://localhost' /etc/init.d/tunnel 2>/dev/null || grep -q 'ExecStart=.*--url http://localhost' /etc/systemd/system/tunnel.service 2>/dev/null; then
                        sed -i 's|\(http://localhost:\)[0-9]\{1,5\}|\1'"$argo_port"'|' /etc/systemd/system/tunnel.service
                        restart_argo
                        get_quick_tunnel
                        change_argo_domain
                    else
                        yellow "你当前使用固定隧道隧道token，请在cloudflared后台修改隧道端口为：$argo_port"
                        restart_argo
                    fi
                fi
                green "ARGO 端口已修改\n"
                ;;
            2)
                reading "\n请输入grpc-reality端口 (回车跳过将使用随机端口): " new_port
                [ -z "$new_port" ] && new_port=$(shuf -i 2000-65000 -n 1)
                until [[ -z $(netstat -tuln | grep -w tcp | awk '{print $4}' | sed 's/.*://g' | grep -w "$new_port") ]]; do
                    if [[ -n $(netstat -tuln | grep -w tcp | awk '{print $4}' | sed 's/.*://g' | grep -w "$new_port") ]]; then
                        echo -e "${red}${new_port}端口已经被其他程序占用，请更换端口重试${re}"
                        reading "请输入新的订阅端口(1-65535):" new_port
                        [[ -z $new_port ]] && new_port=$(shuf -i 2000-65000 -n 1)
                    fi
                done
                sed -i "41s/[0-9]\{1,5\}/$new_port/" /etc/xray/config.json
                restart_xray
                sed -i '1s/\(vless:\/\/[^@]*@[^:]*:\)[0-9]\{1,\}/\1'"$new_port"'/' $client_dir
                base64 -w0 $client_dir > /etc/xray/sub.txt
                while IFS= read -r line; do yellow "$line"; done < ${work_dir}/url.txt
                green "\nGRPC-reality端口已修改成：${purple}$new_port${re} ${green}请更新订阅或手动更改grpc-reality节点端口${re}\n"
                ;;
            3)  change_config ;;
            *)  red "无效的选项，请输入 1 到 3" ;;
        esac
        ;;
    2)
        reading "\n请输入新的UUID: " new_uuid
        [ -z "$new_uuid" ] && new_uuid=$(cat /proc/sys/kernel/random/uuid)
        sed -i "s/[a-fA-F0-9]\{8\}-[a-fA-F0-9]\{4\}-[a-fA-F0-9]\{4\}-[a-fA-F0-9]\{4\}-[a-fA-F0-9]\{12\}/$new_uuid/g" $config_dir
        restart_xray
        sed -i "s/[a-fA-F0-9]\{8\}-[a-fA-F0-9]\{4\}-[a-fA-F0-9]\{4\}-[a-fA-F0-9]\{4\}-[a-fA-F0-9]\{12\}/$new_uuid/g" $client_dir
        content=$(cat "$client_dir")
        vmess_urls=$(grep -o 'vmess://[^ ]*' "$client_dir")
        vmess_prefix="vmess://"
        for vmess_url in $vmess_urls; do
            encoded_vmess="${vmess_url#"$vmess_prefix"}"
            decoded_vmess=$(echo "$encoded_vmess" | base64 --decode)
            updated_vmess=$(echo "$decoded_vmess" | jq --arg new_uuid "$new_uuid" '.id = $new_uuid')
            encoded_updated_vmess=$(echo "$updated_vmess" | base64 | tr -d '\n')
            new_vmess_url="$vmess_prefix$encoded_updated_vmess"
            content=$(echo "$content" | sed "s|$vmess_url|$new_vmess_url|")
        done
        echo "$content" > "$client_dir"
        base64 -w0 $client_dir > /etc/xray/sub.txt
        while IFS= read -r line; do yellow "$line"; done < $client_dir
        green "\nUUID已修改为：${purple}${new_uuid}${re} ${green}请更新订阅或手动更改所有节点的UUID${re}\n"
        ;;
    3)  
        clear
        green "\n1. bgk.jp\n\n2. www.joom.com\n\n3. www.stengg.com\n\n4. www.nazhumi.com\n"  
        reading "\n请输入新的Reality伪装域名(可自定义输入,回车留空将使用默认1): " new_sni
            if [ -z "$new_sni" ]; then    
                new_sni="bgk.jp"
            elif [[ "$new_sni" == "1" ]]; then
                new_sni="bgk.jp"
            elif [[ "$new_sni" == "2" ]]; then
                new_sni="www.joom.com"
            elif [[ "$new_sni" == "3" ]]; then
                new_sni="www.stengg.com"
            elif [[ "$new_sni" == "4" ]]; then
                new_sni="www.nazhumi.com"
            else
                new_sni="$new_sni"
            fi
            jq --arg new_sni "$new_sni" '.inbounds[5].streamSettings.realitySettings.dest = ($new_sni + ":443") | .inbounds[5].streamSettings.realitySettings.serverNames = [$new_sni]' /etc/xray/config.json > /etc/xray/config.json.tmp && mv /etc/xray/config.json.tmp /etc/xray/config.json
            restart_xray 
            sed -i "1s/\(vless:\/\/[^\?]*\?\([^\&]*\&\)*sni=\)[^&]*/\1$new_sni/" $client_dir
            sed -i "1s/\(vless:\/\/[^\?]*\?\([^\&]*\&\)*authority=\)[^&]*/\1$new_sni/" $client_dir
            base64 -w0 $client_dir > /etc/xray/sub.txt
            while IFS= read -r line; do yellow "$line"; done < ${work_dir}/url.txt
            echo ""
            green "\nReality sni已修改为：${purple}${new_sni}${re} ${green}请更新订阅或手动更改reality节点的sni域名${re}\n"
        ;; 
    4)  menu ;;
    *)  read "无效的选项！" ;; 
esac
}

disable_open_sub() {
if [ ${check_xray} -eq 0 ]; then
    clear
    echo ""
    green "1. 关闭节点订阅"
    skyblue "------------"
    green "2. 开启节点订阅"
    skyblue "------------"
    green "3. 更换订阅端口"
    skyblue "------------"
    purple "4. 返回主菜单"
    skyblue "------------"
    reading "请输入选择: " choice
    case "${choice}" in
        1)
            if command -v caddy &>/dev/null; then
                if [ -f /etc/alpine-release ]; then
                    rc-service caddy status | grep -q "started" && rc-service caddy stop || red "caddy not running"
                else 
                    [ "$(systemctl is-active caddy)" = "active" ] && systemctl stop caddy || red "ngixn not running"
                fi
            else
                yellow "caddy is not installed"
            fi

            green "\n已关闭节点订阅\n"     
            ;; 
        2)
            green "\n已开启节点订阅\n"
            server_ip=$(get_realip)
            password=$(tr -dc A-Za-z < /dev/urandom | head -c 32) 
            sed -i "s/\/[a-zA-Z0-9]\+/\/$password/g" /etc/caddy/Caddyfile
	        sub_port=$(port=$(grep -oP ':\K[0-9]+' /etc/caddy/Caddyfile); if [ "$port" -eq 80 ]; then echo ""; else echo "$port"; fi)
            start_caddy
            (port=$(grep -oP ':\K[0-9]+' /etc/caddy/Caddyfile); if [ "$port" -eq 80 ]; then echo ""; else green "订阅端口：$port"; fi); link=$(if [ -z "$sub_port" ]; then echo "http://$server_ip/$password"; else echo "http://$server_ip:$sub_port/$password"; fi); green "\n新的节点订阅链接：$link\n"
            ;; 

        3)
            reading "请输入新的订阅端口(1-65535):" sub_port
            [ -z "$sub_port" ] && sub_port=$(shuf -i 2000-65000 -n 1)
            until [[ -z $(netstat -tuln | grep -w tcp | awk '{print $4}' | sed 's/.*://g' | grep -w "$sub_port") ]]; do
                if [[ -n $(netstat -tuln | grep -w tcp | awk '{print $4}' | sed 's/.*://g' | grep -w "$sub_port") ]]; then
                    echo -e "${red}${new_port}端口已经被其他程序占用，请更换端口重试${re}"
                    reading "请输入新的订阅端口(1-65535):" sub_port
                    [[ -z $sub_port ]] && sub_port=$(shuf -i 2000-65000 -n 1)
                fi
            done
            sed -i "s/:[0-9]\+/:$sub_port/g" /etc/caddy/Caddyfile
            path=$(sed -n 's/.*handle \/\([^ ]*\).*/\1/p' /etc/caddy/Caddyfile)
            server_ip=$(get_realip)
            restart_caddy
            green "\n订阅端口更换成功\n"
            green "新的订阅链接为：http://$server_ip:$sub_port/$path\n"
            ;; 
        4)  menu ;; 
        *)  red "无效的选项！" ;;
    esac
else
    yellow "xray—2go 尚未安装！"
    sleep 1
    menu
fi
}

# xray 管理
manage_xray() {
    green "1. 启动xray服务"
    skyblue "-------------------"
    green "2. 停止xray服务"
    skyblue "-------------------"
    green "3. 重启xray服务"
    skyblue "-------------------"
    purple "4. 返回主菜单"
    skyblue "------------"
    reading "\n请输入选择: " choice
    case "${choice}" in
        1) start_xray ;;  
        2) stop_xray ;;
        3) restart_xray ;;
        4) menu ;;
        *) red "无效的选项！" ;;
    esac
}

# Argo 管理
manage_argo() {
if [ ${check_argo} -eq 2 ]; then
    yellow "Argo 尚未安装！"
    sleep 1
    menu
else
    clear
    echo ""
    green "1. 启动Argo服务"
    skyblue "------------"
    green "2. 停止Argo服务"
    skyblue "------------"
    green "3. 添加Argo固定隧道"
    skyblue "----------------"
    green "4. 切换回Argo临时隧道"
    skyblue "------------------"
    green "5. 重新获取Argo临时域名"
    skyblue "-------------------"
    purple "6. 返回主菜单"
    skyblue "-----------"
    reading "\n请输入选择: " choice
    case "${choice}" in
        1)  start_argo ;;
        2)  stop_argo ;; 
        3)
            clear
            yellow "\n固定隧道可为json或token，固定隧道端口为8080，自行在cf后台设置\n\njson在f佬维护的站点里获取，获取地址：${purple}https://fscarmen.cloudflare.now.cc${re}\n"
            reading "\n请输入你的argo域名: " argo_domain
            green "你的Argo域名为：$argo_domain"
            ArgoDomain=$argo_domain
            reading "\n请输入你的argo密钥(token或json): " argo_auth
            if [[ $argo_auth =~ TunnelSecret ]]; then
                echo $argo_auth > ${work_dir}/tunnel.json
                cat > ${work_dir}/tunnel.yml << EOF
tunnel: $(cut -d\" -f12 <<< "$argo_auth")
credentials-file: ${work_dir}/tunnel.json
protocol: http2
                                           
ingress:
  - hostname: $ArgoDomain
    service: http://localhost:8080
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
                if [ -f /etc/alpine-release ]; then
                    sed -i '/^command_args=/c\command_args="-c '\''/etc/xray/argo tunnel --edge-ip-version auto --config /etc/xray/tunnel.yml run 2>&1'\''"' /etc/init.d/tunnel
                else
                    sed -i '/^ExecStart=/c ExecStart=/bin/sh -c "/etc/xray/argo tunnel --edge-ip-version auto --config /etc/xray/tunnel.yml run 2>&1"' /etc/systemd/system/tunnel.service
                fi
                restart_argo
                change_argo_domain

            elif [[ $argo_auth =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
                if [ -f /etc/alpine-release ]; then
                    sed -i "/^command_args=/c\command_args=\"-c '/etc/xray/argo tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token $argo_auth 2>&1'\"" /etc/init.d/tunnel
                else

                    sed -i '/^ExecStart=/c ExecStart=/bin/sh -c "/etc/xray/argo tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token '$argo_auth' 2>&1"' /etc/systemd/system/tunnel.service
                fi
                restart_argo
                change_argo_domain
            else
                yellow "你输入的argo域名或token不匹配，请重新输入"
                manage_argo            
            fi
            ;; 
        4)
            clear
            if [ -f /etc/alpine-release ]; then
                alpine_openrc_services
            else
                main_systemd_services
            fi
            get_quick_tunnel
            change_argo_domain 
            ;; 

        5)  
            if [ -f /etc/alpine-release ]; then
                if grep -q '--url http://localhost:8080' /etc/init.d/tunnel; then
                    get_quick_tunnel
                    change_argo_domain 
                else
                    yellow "当前使用固定隧道，无法获取临时隧道"
                    sleep 2
                    menu
                fi
            else
                if grep -q 'ExecStart=.*--url http://localhost:8080' /etc/systemd/system/tunnel.service; then
                    get_quick_tunnel
                    change_argo_domain 
                else
                    yellow "当前使用固定隧道，无法获取临时隧道"
                    sleep 2
                    menu
                fi
            fi 
            ;; 
        6)  menu ;; 
        *)  red "无效的选项！" ;;
    esac
fi
}

# 获取argo临时隧道
get_quick_tunnel() {
restart_argo
yellow "获取临时argo域名中，请稍等...\n"
sleep 6
get_argodomain=$(grep -oE 'https://[[:alnum:]+\.-]+\.trycloudflare\.com' /etc/xray/argo.log | sed 's@https://@@')
green "ArgoDomain：${purple}$get_argodomain${re}"
ArgoDomain=$get_argodomain
}


# 更新Argo域名到订阅
change_argo_domain() {
    sed -i "3s/sni=[^&]*/sni=$ArgoDomain/; 3s/host=[^&]*/host=$ArgoDomain/" /etc/xray/url.txt
    content=$(cat "$client_dir")
    vmess_urls=$(grep -o 'vmess://[^ ]*' "$client_dir")
    vmess_prefix="vmess://"
    for vmess_url in $vmess_urls; do
        encoded_vmess="${vmess_url#"$vmess_prefix"}"
        decoded_vmess=$(echo "$encoded_vmess" | base64 --decode)
        updated_vmess=$(echo "$decoded_vmess" | jq --arg new_domain "$ArgoDomain" '.host = $new_domain | .sni = $new_domain')
        encoded_updated_vmess=$(echo "$updated_vmess" | base64 | tr -d '\n')
        new_vmess_url="$vmess_prefix$encoded_updated_vmess"
        content=$(echo "$content" | sed "s|$vmess_url|$new_vmess_url|")
    done
    echo "$content" > "$client_dir"
    base64 -w0 ${work_dir}/url.txt > ${work_dir}/sub.txt

    while IFS= read -r line; do echo -e "${purple}$line"; done < "$client_dir"
    
    green "\nv节点已更新,更新订阅或手动复制以上节点\n"
}

# 查看节点信息和订阅链接
check_nodes() {
if [ ${check_xray} -eq 0 ]; then
    while IFS= read -r line; do purple "${purple}$line"; done < ${work_dir}/url.txt
    server_ip=$(get_realip)
    sub_port=$(grep -oP ':\K[0-9]+' /etc/caddy/Caddyfile)
    lujing=$(grep -oP 'handle /\K[a-zA-Z0-9]+' /etc/caddy/Caddyfile)
    green "\n\n节点订阅链接：http://$server_ip:$sub_port/$lujing\n"
else 
    yellow "Xray-2go 尚未安装或未运行,请先安装或启动Xray-2go"
    sleep 1
    menu
fi
}

# 捕获 Ctrl+C 信号
trap 'red "已取消操作"; exit' INT

# 主菜单
menu() {
while true; do
   check_xray &>/dev/null; check_xray=$?
   check_caddy &>/dev/null; check_caddy=$?
   check_argo &>/dev/null; check_argo=$?
   check_xray_status=$(check_xray)
   check_caddy_status=$(check_caddy)
   check_argo_status=$(check_argo)
   clear
   echo ""
   purple "=== 老王Xray-2go一键安装脚本 ===\n"
   purple " Xray 状态: ${check_xray_status}\n"
   purple " Argo 状态: ${check_argo_status}\n"   
   purple "Caddy 状态: ${check_caddy_status}\n"
   green "1. 安装Xray-2go"
   red "2. 卸载Xray-2go"
   echo "==============="
   green "3. Xray-2go管理"
   green "4. Argo隧道管理"
   echo  "==============="
   green  "5. 查看节点信息"
   green  "6. 修改节点配置"
   green  "7. 管理节点订阅"
   echo  "==============="
   purple "8. ssh综合工具箱"
   purple "9. 安装singbox四合一"
   echo  "==============="
   red "0. 退出脚本"
   echo "==========="
   reading "请输入选择(0-8): " choice
   echo ""
   case "${choice}" in
        1)  
            if [ ${check_xray} -eq 0 ]; then
                yellow "Xray-2go 已经安装！"
            else
                manage_packages install caddy jq unzip iptables openssl
                install_xray

                if [ -x "$(command -v systemctl)" ]; then
                    main_systemd_services
                elif [ -x "$(command -v rc-update)" ]; then
                    alpine_openrc_services
                    change_hosts
                    rc-service xray restart
                    rc-service tunnel restart
                else
                    echo "Unsupported init system"
                    exit 1 
                fi

                sleep 5
                get_info
                add_caddy_conf
                create_shortcut
            fi
           ;;
        2) uninstall_xray ;;
        3) manage_xray ;;
        4) manage_argo ;;
        5) check_nodes ;;
        6) change_config ;;
        7) disable_open_sub ;;
        8) clear && curl -fsSL https://raw.githubusercontent.com/eooce/ssh_tool/main/ssh_tool.sh -o ssh_tool.sh && chmod +x ssh_tool.sh && ./ssh_tool.sh ;;           
        9) clear && bash <(curl -Ls https://raw.githubusercontent.com/eooce/sing-box/main/sing-box.sh) ;;
        0) exit 0 ;;
        *) red "无效的选项，请输入 0 到 9" ;; 
   esac
   read -n 1 -s -r -p $'\033[1;91m按任意键继续...\033[0m'
done
}
menu
