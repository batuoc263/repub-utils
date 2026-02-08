#!/bin/bash

# --- Cấu hình ---
REPUBLIC_HOME="$HOME/.republicd"
KEYRING_BACKEND="test"
CHAIN_ID="raitestnet_77701-1"
RPC="https://rpc.republicai.io:443"
WALLET_NAME="wallet"
FEES="100000000000000000arai" # 0.1 RAI

# 1. Lấy địa chỉ Validator
VAL_ADDR=$(republicd keys show $WALLET_NAME --bech val -a --home "$REPUBLIC_HOME" --keyring-backend "$KEYRING_BACKEND" 2>/dev/null)

if [ -z "$VAL_ADDR" ]; then
    echo "$(date) - [ERROR] Không lấy được địa chỉ validator. Kiểm tra lại keyname hoặc thư mục home."
    exit 1
fi

# 2. Query trạng thái từ RPC
STATUS_JSON=$(republicd query staking validator $VAL_ADDR --node "$RPC" --output json 2>/dev/null)

# Kiểm tra nếu query thất bại (RPC die hoặc node chưa sync block đó)
if [ -z "$STATUS_JSON" ]; then
    echo "$(date) - [ERROR] Không thể kết nối RPC hoặc không tìm thấy dữ liệu validator."
    exit 1
fi

# 3. Trích xuất thông tin Jailed và Status
JAILED=$(echo $STATUS_JSON | jq -r '.validator.jailed')
STATUS=$(echo $STATUS_JSON | jq -r '.validator.status')

# 4. Kiểm tra đồng bộ (Syncing) của node cục bộ
# Lưu ý: Lệnh status này check node đang chạy trên máy bạn
SYNCING=$(republicd status --home "$REPUBLIC_HOME" 2>&1 | jq -r '.sync_info.catching_up')

echo "$(date) - Node: $STATUS | Jailed: $JAILED | Catching_up: $SYNCING"

# --- Logic xử lý ---
if [ "$JAILED" == "true" ]; then
    if [ "$SYNCING" == "false" ]; then
        echo "$(date) - [ACTION] Node bị Jailed. Đang tiến hành gửi lệnh Unjail..."
        
        republicd tx slashing unjail \
            --from $WALLET_NAME \
            --chain-id $CHAIN_ID \
            --home "$REPUBLIC_HOME" \
            --keyring-backend "$KEYRING_BACKEND" \
            --gas auto --gas-adjustment 1.5 \
            --fees $FEES \
            --node "$RPC" -y
            
        echo "$(date) - [INFO] Đã thực thi lệnh Unjail."
    else
        echo "$(date) - [WAIT] Node bị Jailed nhưng chưa đồng bộ xong. Không thực hiện unjail."
    fi
else
    echo "$(date) - [OK] Node vẫn hoạt động bình thường."
fi
