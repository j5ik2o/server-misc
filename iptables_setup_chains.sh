#!/bin/bash

IPTABLES=/usr/sbin/iptables

# アドレスリスト取得
. ./iptables_functions

GET_IPLIST

# ---
# 独自チェイン定義
# ---

# 日本
ACCEPT_COUNTRY_MAKE JP

$IPTABLES -N ACCEPT_COUNTRY
$IPTABLES -A ACCEPT_COUNTRY -j ACCEPT_JP

# 中国・韓国・台湾
DROP_COUNTRY_MAKE CN
DROP_COUNTRY_MAKE KR
DROP_COUNTRY_MAKE TW

$IPTABLES -N DROP_COUNTRY
$IPTABLES -A DROP_COUNTRY -j DROP_CN
$IPTABLES -A DROP_COUNTRY -j DROP_KR
$IPTABLES -A DROP_COUNTRY -j DROP_TW

# モバイルキャリア
ACCEPT_SOURCE_MAKE SOFTBANK ./carrier/softbank.lst
ACCEPT_SOURCE_MAKE AU ./carrier/au.lst
ACCEPT_SOURCE_MAKE DOCOMO ./carrier/docomo.lst

$IPTABLES -N ACCEPT_MOBILE
$IPTABLES -A ACCEPT_MOBILE -j ACCEPT_SOFTBANK
$IPTABLES -A ACCEPT_MOBILE -j ACCEPT_AU
$IPTABLES -A ACCEPT_MOBILE -j ACCEPT_DOCOMO

# モバイルキャリア
DROP_SOURCE_MAKE SOFTBANK ./carrier/softbank.lst
DROP_SOURCE_MAKE AU ./carrier/au.lst
DROP_SOURCE_MAKE DOCOMO ./carrier/docomo.lst

$IPTABLES -N DROP_MOBILE
$IPTABLES -A DROP_MOBILE -j DROP_SOFTBANK
$IPTABLES -A DROP_MOBILE -j DROP_AU
$IPTABLES -A DROP_MOBILE -j DROP_DOCOMO
