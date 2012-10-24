#!/bin/bash

#---------------------------------------#
# 設定開始                              #
#---------------------------------------#

# インタフェース名定義
LAN=eth0

HTTP_PORT=80
IDENT_PORT=113

#---------------------------------------#
# 設定終了                              #
#---------------------------------------#

# 内部ネットワークのネットマスク取得
LOCALNET_MASK=`LANG=C ifconfig $LAN|sed -e 's/^.*Mask:\([^ ]*\)$/\1/p' -e d`

# 内部ネットワークアドレス取得
LOCALNET_ADDR=`LANG=C netstat -rn|grep $LAN|grep $LOCALNET_MASK|cut -f1 -d' '`
LOCALNET=$LOCALNET_ADDR/$LOCALNET_MASK

# 初期化
iptables -F
iptables -X

# デフォルトルール(以降のルールにマッチしなかった場合に適用するルール)設定
iptables -P INPUT   DROP   # 受信はすべて破棄
iptables -P OUTPUT  ACCEPT # 送信はすべて許可
iptables -P FORWARD DROP   # 通過はすべて破棄

# 自ホストからのアクセスをすべて許可
iptables -A INPUT -i lo -j ACCEPT

# 内部からのアクセスをすべて許可
iptables -A INPUT -s $LOCALNET -j ACCEPT

# ---

# ---
# 接続済みパケットは許可
# 内部から行ったアクセスに対する外部からの返答アクセスを許可
# ---
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# ---
# Stealth Scan
# ---
iptables -N STEALTH_SCAN
iptables -A STEALTH_SCAN -j LOG --log-prefix "[STEALTH_SCAN_ATTACK]: "
iptables -A STEALTH_SCAN -j DROP

iptables -A INPUT -p tcp --tcp-flags SYN,ACK SYN,ACK -m state --state NEW -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j STEALTH_SCAN

iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN         -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST         -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j STEALTH_SCAN

iptables -A INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ACK,FIN FIN     -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ACK,PSH PSH     -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ACK,URG URG     -j STEALTH_SCAN

# ---
# フラグメントパケットによるポートスキャン, DOS攻撃対策
# フラグメント化されたパケットはログを記録して破棄
# ---
iptables -A INPUT -f -j LOG --log-prefix '[FRAGMENT_ATTACK] : '
iptables -A INPUT -f -j DROP

# ---
# Ping of Death Attack
# ---
iptables -N PING_OF_DEATH
iptables -A PING_OF_DEATH -p icmp --icmp-type echo-request \
         -m hashlimit \
         --hashlimit 1/s \
         --hashlimit-burst 10 \
         --hashlimit-htable-expire 300000 \
         --hashlimit-mode srcip \
         --hashlimit-name t_PING_OF_DEATH \
         -j RETURN

iptables -A PING_OF_DEATH -j LOG --log-prefix '[PINGDEATH_ATTACK] : '
iptables -A PING_OF_DEATH -j DROP
iptables -A INPUT -p icmp --icmp-type echo-request -j PING_OF_DEATH

# ---
# SYN Flood Attack
# ---
iptables -N SYN_FLOOD # "SYN_FLOOD" という名前でチェーンを作る
iptables -A SYN_FLOOD -p tcp --syn \
         -m hashlimit \
         --hashlimit 200/s \
         --hashlimit-burst 3 \
         --hashlimit-htable-expire 300000 \
         --hashlimit-mode srcip \
         --hashlimit-name t_SYN_FLOOD \
         -j RETURN

iptables -A SYN_FLOOD -j LOG --log-prefix "[SYN_FLOOD_ATTACK] : "
iptables -A SYN_FLOOD -j DROP
iptables -A INPUT -p tcp --syn -j SYN_FLOOD


# ---
# HTTP DoS/DDos Attack
# ---
iptables -N HTTP_DOS
iptables -A HTTP_DOS -p tcp -m multiport --dports $HTTP_PORT \
         -m hashlimit \
         --hashlimit 1/s \
         --hashlimit-burst 100 \
         --hashlimit-htable-expire 300000 \
         --hashlimit-mode srcip \
         --hashlimit-name t_HTTP_DOS \
         -j RETURN

iptables -A HTTP_DOS -j LOG --log-prefix "[HTTP_DOS_ATTACK] : "
iptables -A HTTP_DOS -j DROP

iptables -A INPUT -p tcp -m multiport --dports $HTTP_PORT -j HTTP_DOS

# ---
# IDENT port probe Attack
# ---
iptables -A INPUT -p tcp -m multiport --dports $IDENT_PORT -j REJECT --reject-with tcp-reset


# ---
# SSH Brute Force Attack
# ---
iptables -A INPUT -p tcp --syn -m multiport --dports $SSH_PORT -m recent --name ssh_attack --set
iptables -A INPUT -p tcp --syn -m multiport --dports $SSH_PORT -m recent --name ssh_attack --rcheck --seconds 60 --hitcount 5 -j LOG --log-prefix "[SSH_BRUTE_FORCE] : "
iptables -A INPUT -p tcp --syn -m multiport --dports $SSH_PORT -m recent --name ssh_attack --rcheck --seconds 60 --hitcount 5 -j REJECT --reject-with tcp-reset

# ---
# 全ホスト(ブロードキャストアドレス、マルチキャストアドレス)宛パケットはログを記録せずに破棄
# ---
iptables -A INPUT -d 192.168.1.255   -j LOG --log-prefix "[DROP_BROADCAST] : "
iptables -A INPUT -d 192.168.1.255   -j DROP
iptables -A INPUT -d 255.255.255.255 -j LOG --log-prefix "[DROP_BROADCAST] : "
iptables -A INPUT -d 255.255.255.255 -j DROP
iptables -A INPUT -d 224.0.0.1       -j LOG --log-prefix "[DROP_BROADCAST] : "
iptables -A INPUT -d 224.0.0.1       -j DROP

# 外部とのNetBIOS関連のアクセスはログを記録せずに破棄
# ※不要ログ記録防止
iptables -A INPUT ! -s $LOCALNET -p tcp -m multiport --dports 135,137,138,139,445 -j DROP
iptables -A INPUT ! -s $LOCALNET -p udp -m multiport --dports 135,137,138,139,445 -j DROP
iptables -A OUTPUT ! -d $LOCALNET -p tcp -m multiport --sports 135,137,138,139,445 -j DROP
iptables -A OUTPUT ! -d $LOCALNET -p udp -m multiport --sports 135,137,138,139,445 -j DROP

# ---
# 全ホストからの入力許可
# ---
# icmp
iptables -A INPUT -p icmp -j ACCEPT

# ssh
iptables -A INPUT -p tcp --dport 22 -j ACCEPT_COUNTRY

# elmo api
iptables -A INPUT -p tcp --dport 8081:8082 -j ACCEPT_COUNTRY

# elmo voip
iptables -A INPUT -p udp --dport 10001 -j ACCEPT_COUNTRY




# ブロードキャストアドレス宛pingには応答しない
# ※Smurf攻撃対策
sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1 > /dev/null
sed -i '/net.ipv4.icmp_echo_ignore_broadcasts/d' /etc/sysctl.conf
echo "net.ipv4.icmp_echo_ignore_broadcasts=1" >> /etc/sysctl.conf

# ICMP Redirectパケットは拒否
sed -i '/net.ipv4.conf.*.accept_redirects/d' /etc/sysctl.conf
for dev in `ls /proc/sys/net/ipv4/conf/`
do
    sysctl -w net.ipv4.conf.$dev.accept_redirects=0 > /dev/null
    echo "net.ipv4.conf.$dev.accept_redirects=0" >> /etc/sysctl.conf
done

# Source Routedパケットは拒否
sed -i '/net.ipv4.conf.*.accept_source_route/d' /etc/sysctl.conf
for dev in `ls /proc/sys/net/ipv4/conf/`
do
    sysctl -w net.ipv4.conf.$dev.accept_source_route=0 > /dev/null
    echo "net.ipv4.conf.$dev.accept_source_route=0" >> /etc/sysctl.conf
done





# アドレスリスト取得
. /root/script/iptables_functions
IPLISTGET

echo "start country"
# 日本からのアクセスを許可するユーザ定義チェインACCEPT_COUNTRY作成
iptables -N ACCEPT_COUNTRY
ACCEPT_COUNTRY_MAKE JP
# 以降,日本からのみアクセスを許可したい場合はACCEPTのかわりにACCEPT_COUNTRYを指定する

# 中国・韓国・台湾※からのアクセスをログを記録して破棄
# ※全国警察施設への攻撃元上位３カ国(日本・アメリカを除く)
# http://www.cyberpolice.go.jp/detect/observation.htmlより
iptables -N DROP_COUNTRY
DROP_COUNTRY_MAKE CN
DROP_COUNTRY_MAKE KR
DROP_COUNTRY_MAKE TW
iptables -A INPUT -j DROP_COUNTRY
echo "end country"

# 上記のルールにマッチしなかったアクセスはログを記録して破棄
iptables -A INPUT -m limit --limit 1/s -j LOG --log-prefix '[IPTABLES INPUT] : '
iptables -A INPUT -j DROP
iptables -A FORWARD -m limit --limit 1/s -j LOG --log-prefix '[IPTABLES FORWARD] : '
iptables -A FORWARD -j DROP

echo "start iptables-save"
iptables-save -c > /etc/iptables-save
echo "end iptables-save"
