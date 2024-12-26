# iptables設定スクリプト

このスクリプト群は、Ubuntuサーバー向けの高度なiptables設定を自動化するためのツールセットです。国別IPアドレスフィルタリング、DoS/DDoS対策、ステルススキャン対策など、包括的なセキュリティ機能を提供します。

## 主な機能

- 国別IPアドレスフィルタリング（デフォルトで日本からのアクセスのみ許可）
- モバイルキャリア別アクセス制御
- 各種攻撃対策
  - Stealth Scan Attack
  - Ping of Death
  - SYN Flood Attack
  - HTTP DoS/DDoS Attack
  - SSH Brute Force Attack
- ブロードキャスト・マルチキャストパケットの制御
- システムパラメータの自動最適化

## ファイル構成

- `iptables.sh`: メインスクリプト。基本的なファイアウォールルールを設定
- `iptables_config.template.sh`: ユーザー設定用テンプレート
- `iptables_setup_chains.sh`: 国別・キャリア別チェインの設定
- `iplist_check.sh`: IPアドレスリストの更新確認と適用
- `iptables_functions`: 共通関数定義ファイル

## セットアップ手順

1. 設定ファイルの準備
```bash
cp iptables_config.template.sh iptables_config.sh
```

2. `iptables_config.sh`の編集
   - インターフェース名の設定
   - 許可/拒否するホストの設定
   - カスタムルールの追加

3. キャリアリストの準備（必要な場合）
```bash
mkdir carrier
# 各キャリアのIPリストを配置
```

## 使用方法

### 基本的な設定の適用
```bash
sudo ./iptables.sh
```

### IPリストの更新チェックと適用
```bash
sudo ./iplist_check.sh
```

### 定期的な更新の設定
```bash
# crontabの例
0 4 * * * /path/to/iplist_check.sh
```

## カスタマイズ

### 国別フィルタリングの設定

`iplist_check.sh`の`COUNTRY_CODE`変数で対象国を指定：
```bash
COUNTRY_CODE='JP CN TW RU'
```

### 新規ルールの追加

`iptables_config.sh`の`USER_CONFIG`関数内にカスタムルールを追加：
```bash
USER_CONFIG() {
    # 例：特定ポートの許可
    $IPTABLES -A INPUT -p tcp --dport 8080 -j ACCEPT_COUNTRY
}
```

## セキュリティ機能

### DoS/DDoS対策
- hashlimitモジュールを使用した接続制限
- SYN Cookie保護の有効化
- フラグメントパケットの制御

### スキャン対策
- ステルススキャン検出と遮断
- SSHブルートフォース攻撃の防止
- 不正なTCPフラグの検出

### システム保護
- ICMPリダイレクトの無効化
- ソースルーティングの無効化
- ブロードキャストPingの無効化

## ログ管理

すべての重要なイベントは以下のプレフィックスでログに記録されます：
- `[NF:STEALTH_SCAN]`
- `[NF:FRAGMENT_ATTACK]`
- `[NF:PINGDEATH:ATCK]`
- `[NF:SYN_FLOOD:ATCK]`
- `[NF:HTTP_DOS:ATCK]`
- `[NF:SSH_BRUTE_FORCE]`
など

## トラブルシューティング

1. IPリスト更新エラー
   - `/tmp/cidr.txt`のバックアップ確認
   - ネットワーク接続の確認
   - プロキシ設定の確認

2. ルール適用エラー
   - `iptables-save`の出力確認
   - システムログの確認
   - `DEBUG=1`オプションでの実行

## 注意事項

- 本番環境への適用前に必ずテスト環境での動作確認を行ってください
- SSHアクセスをブロックしないよう、`ACCEPT_COUNTRY`の設定に注意してください
- システムリソースの使用状況を定期的に監視してください
