#!/bin/sh

#---------------------------------------#
# 設定開始                              #
#---------------------------------------#
IPTABLES=/sbin/iptables

# インタフェース名定義
LAN=eth0

HTTP_PORT=80,8081,8082
IDENT_PORT=113
SSH_PORT=22

ALLOW_HOSTS=("221.243.26.162/32")

USER_CONFIG() {

# ssh
$IPTABLES -A INPUT -p tcp --dport 22 -j ACCEPT_COUNTRY

# elmo 
$IPTABLES -A INPUT -p tcp --dport 8081:8082 -j ACCEPT_MOBILE
$IPTABLES -A INPUT -p udp --dport 10001 -j ACCEPT_MOBILE

}

#---------------------------------------#
# 設定終了                              #
#---------------------------------------#

# アドレスリスト取得
. ./iptables_functions

# 内部ネットワークのネットマスク取得
LOCALNET_MASK=`LANG=C ifconfig $LAN|sed -e 's/^.*Mask:\([^ ]*\)$/\1/p' -e d`

# 内部ネットワークアドレス取得
LOCALNET_ADDR=`LANG=C netstat -rn|grep $LAN|grep $LOCALNET_MASK|cut -f1 -d' '`
LOCALNET=$LOCALNET_ADDR/$LOCALNET_MASK

# 初期化
$IPTABLES -F
$IPTABLES -X

$IPTABLES -P INPUT   DROP   # 受信はすべて破棄
$IPTABLES -P OUTPUT  ACCEPT # 送信はすべて許可
$IPTABLES -P FORWARD DROP   # 通過はすべて破棄

# 自ホストからのアクセスをすべて許可
$IPTABLES -A INPUT -i lo -j ACCEPT

# 内部からのアクセスをすべて許可
$IPTABLES -A INPUT -s $LOCALNET -j ACCEPT

# ---
# 接続済みパケットは許可
# 内部から行ったアクセスに対する外部からの返答アクセスを許可
# ---
$IPTABLES -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

if [ "${ALLOW_HOSTS[@]}" ]; then
  for ALLOW_HOST in ${ALLOW_HOSTS[@]}
  do
    $IPTABLES -A INPUT -p tcp -s $ALLOW_HOST -j ACCEPT
  done
fi

if [ "${DENY_HOSTS[@]}" ]; then
  for DENY_HOST in ${DENY_HOSTS[@]}
  do
    $IPTABLES -A INPUT -s $DENY_HOST -m limit --limit 1/s -j LOG --log-prefix "[NF:DENY_HOST] : "
    $IPTABLES -A INPUT -s $DENY_HOST -j DROP
  done
fi

sh ./iptables_setup_chains.sh 

# デフォルトで日本以外からは受け付けない
$IPTABLES -A INPUT -j DROP_COUNTRY

# ---
# Stealth Scan Attack
# ---
$IPTABLES -N STEALTH_SCAN
$IPTABLES -A STEALTH_SCAN -j LOG --log-prefix "[NF:STEALTH_SCAN] : "
$IPTABLES -A STEALTH_SCAN -j DROP

$IPTABLES -A INPUT -p tcp --tcp-flags SYN,ACK SYN,ACK -m state --state NEW -j STEALTH_SCAN
$IPTABLES -A INPUT -p tcp --tcp-flags ALL NONE -j STEALTH_SCAN

$IPTABLES -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN         -j STEALTH_SCAN
$IPTABLES -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST         -j STEALTH_SCAN
$IPTABLES -A INPUT -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j STEALTH_SCAN

$IPTABLES -A INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j STEALTH_SCAN
$IPTABLES -A INPUT -p tcp --tcp-flags ACK,FIN FIN     -j STEALTH_SCAN
$IPTABLES -A INPUT -p tcp --tcp-flags ACK,PSH PSH     -j STEALTH_SCAN
$IPTABLES -A INPUT -p tcp --tcp-flags ACK,URG URG     -j STEALTH_SCAN

# ---
# フラグメントパケットによるポートスキャン, DOS攻撃対策
# フラグメント化されたパケットはログを記録して破棄
# ---
$IPTABLES -A INPUT -f -j LOG --log-prefix '[NF:FRAGMENT_ATTACK] : '
$IPTABLES -A INPUT -f -j DROP

# ---
# Ping of Death Attack
# ---
$IPTABLES -N PING_OF_DEATH
$IPTABLES -A PING_OF_DEATH -p icmp --icmp-type echo-request \
         -m hashlimit \
         --hashlimit 1/s \
         --hashlimit-burst 10 \
         --hashlimit-htable-expire 300000 \
         --hashlimit-mode srcip \
         --hashlimit-name t_PING_OF_DEATH \
         -j RETURN

$IPTABLES -A PING_OF_DEATH -j LOG --log-prefix '[NF:PINGDEATH:ATCK] : '
$IPTABLES -A PING_OF_DEATH -j DROP
$IPTABLES -A INPUT -p icmp --icmp-type echo-request -j PING_OF_DEATH


# ---
# SYN Flood Attack
# ---
$IPTABLES -N SYN_FLOOD # "SYN_FLOOD" という名前でチェーンを作る
$IPTABLES -A SYN_FLOOD -p tcp --syn \
         -m hashlimit \
         --hashlimit 200/s \
         --hashlimit-burst 3 \
         --hashlimit-htable-expire 300000 \
         --hashlimit-mode srcip \
         --hashlimit-name t_SYN_FLOOD \
         -j RETURN

$IPTABLES -A SYN_FLOOD -j LOG --log-prefix "[NF:SYN_FLOOD:ATCK] : "
$IPTABLES -A SYN_FLOOD -j DROP
$IPTABLES -A INPUT -p tcp --syn -j SYN_FLOOD

# ---
# HTTP DoS/DDos Attack
# ---
$IPTABLES -N HTTP_DOS
$IPTABLES -A HTTP_DOS -p tcp -m multiport --dports $HTTP_PORT \
         -m hashlimit \
         --hashlimit 1/s \
         --hashlimit-burst 100 \
         --hashlimit-htable-expire 300000 \
         --hashlimit-mode srcip \
         --hashlimit-name t_HTTP_DOS \
         -j RETURN

$IPTABLES -A HTTP_DOS -j LOG --log-prefix "[NF:HTTP_DOS:ATCK] : "
$IPTABLES -A HTTP_DOS -j DROP

$IPTABLES -A INPUT -p tcp -m multiport --dports $HTTP_PORT -j HTTP_DOS

# ---
# IDENT port probe Attack
# ---
$IPTABLES -A INPUT -p tcp -m multiport --dports $IDENT_PORT -j REJECT --reject-with tcp-reset

# ---
# SSH Brute Force Attack
# ---
$IPTABLES -A INPUT -p tcp --syn -m multiport --dports $SSH_PORT -m recent --name ssh_attack --set
$IPTABLES -A INPUT -p tcp --syn -m multiport --dports $SSH_PORT -m recent --name ssh_attack --rcheck --seconds 60 --hitcount 5 -j LOG --log-prefix "[NF:SSH_BRUTE_FORCE] : "
$IPTABLES -A INPUT -p tcp --syn -m multiport --dports $SSH_PORT -m recent --name ssh_attack --rcheck --seconds 60 --hitcount 5 -j REJECT --reject-with tcp-reset

# ---
# 全ホスト(ブロードキャストアドレス、マルチキャストアドレス)宛パケットはログを記録せずに破棄
# ---
$IPTABLES -A INPUT -d 192.168.1.255   -j LOG --log-prefix "[NF:DROP_BROADCAST] : "
$IPTABLES -A INPUT -d 192.168.1.255   -j DROP
$IPTABLES -A INPUT -d 255.255.255.255 -j LOG --log-prefix "[NF:DROP_BROADCAST] : "
$IPTABLES -A INPUT -d 255.255.255.255 -j DROP
$IPTABLES -A INPUT -d 224.0.0.1       -j LOG --log-prefix "[NF:DROP_BROADCAST] : "
$IPTABLES -A INPUT -d 224.0.0.1       -j DROP

# 外部とのNetBIOS関連のアクセスはログを記録せずに破棄
$IPTABLES -A INPUT ! -s $LOCALNET -p tcp -m multiport --dports 135,137,138,139,445 -j DROP
$IPTABLES -A INPUT ! -s $LOCALNET -p udp -m multiport --dports 135,137,138,139,445 -j DROP
$IPTABLES -A OUTPUT ! -d $LOCALNET -p tcp -m multiport --sports 135,137,138,139,445 -j DROP
$IPTABLES -A OUTPUT ! -d $LOCALNET -p udp -m multiport --sports 135,137,138,139,445 -j DROP

# ---
# 全ホストからの入力許可
# ---
# icmp
$IPTABLES -A INPUT -p icmp -j ACCEPT_CONTRY

USER_CONFIG

# SynCookies対策
sysctl -w net.ipv4.tcp_syncookies=1 > /dev/null
sed -i '/net.ipv4.tcp_syncookies/d' /etc/sysctl.conf
echo "net.ipv4.tcp_syncookies=1" >> /etc/sysctl.conf

# ブロードキャストアドレス宛pingには応答しない
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

# 上記のルールにマッチしなかったアクセスはログを記録して破棄
$IPTABLES -A INPUT -j LOG --log-prefix '[NF:INPUT] : '
$IPTABLES -A INPUT -j DROP
$IPTABLES -A FORWARD -j LOG --log-prefix '[NF:FORWARD] : '
$IPTABLES -A FORWARD -j DROP

echo "start iptables-save"
iptables-save -c > /etc/iptables-save
echo "end iptables-save"
