# xray-argo无交互一键四协议安装脚本
最好用的一键xray-argo脚本，一键四协议无交互安装脚本！
* vless-grpc-reality | vless-ws-tls(argo) | vmess-ws-tls(argo) | vmess-splithttp-tls(argo)
* splithttp目前支持的客户端较少
* 可选环境变量：UUID CADDY_PORT CFIP CFPORT 自定义变量放脚本前面运行即可
* NAT小鸡需带CADDY_PORT变量运行或运行完后更改订阅端口和grpc-reality端口

```
bash <(curl -Ls https://github.com/eooce/xray-2go/raw/main/xray_2go.sh)
```

带变量运行示例,修改为自己需要定义的参数
```
CADDY_PORT=8888 CFIP=www.visa.com.tw CFPORT=8443 bash <(curl -Ls https://github.com/eooce/xray-2go/raw/main/xray_2go.sh)
```

# 免责声明
* 本程序仅供学习了解, 非盈利目的，请于下载后 24 小时内删除, 不得用作任何商业用途, 文字、数据及图片均有所属版权, 如转载须注明来源。
* 使用本程序必循遵守部署免责声明，使用本程序必循遵守部署服务器所在地、所在国家和用户所在国家的法律法规, 程序作者不对使用者任何不当行为负责。
