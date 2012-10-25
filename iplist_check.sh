#!/bin/sh

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# 新旧IPLIST差分チェック件数(0を指定するとチェックしない)
# ※新旧IPLIST差分がSABUN_CHKで指定した件数を越える場合はiptables設定スクリプトを実行しない
# ※新旧IPLIST差分チェック理由はhttp://centossrv.com/bbshtml/webpatio/1592.shtmlを参照
SABUN_CHK=100
[ $# -ne 0 ] && SABUN_CHK=${1}

# チェック国コード
COUNTRY_CODE='JP CN TW RU'

# iptables設定スクリプトパス
IPTABLES=./iptables.sh

# iptables設定スクリプト外部関数取り込み
. ./iptables_functions

# IPアドレスリスト最新化
rm -f IPLIST.new
GET_IPLIST

for country in $COUNTRY_CODE
do
    if [ -f /tmp/cidr.txt ]; then
        grep ^$country /tmp/cidr.txt >> IPLIST.new
    else
        grep ^$country /tmp/IPLIST >> IPLIST.new
    fi
done
[ ! -f /tmp/IPLIST ] && cp IPLIST.new /tmp/IPLIST

# IPアドレスリスト更新チェック
diff -q /tmp/IPLIST IPLIST.new > /dev/null 2>&1
if [ $? -ne 0 ]; then
    if [ ${SABUN_CHK} -ne 0 ]; then
        if [ $(diff /tmp/IPLIST IPLIST.new | egrep -c '<|>') -gt ${SABUN_CHK} ]; then
            (
             diff /tmp/IPLIST IPLIST.new
             echo
             echo "$IPTABLES not executed."
            ) | mail -s 'IPLIST UPDATE' root
            rm -f IPLIST.new
            exit
        fi
    fi
    /bin/mv IPLIST.new /tmp/IPLIST
    sh $IPTABLES > /dev/null
else
    rm -f IPLIST.new
fi

