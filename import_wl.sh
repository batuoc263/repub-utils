#!/bin/bash

# Đường dẫn file chứa mnemonic
INPUT_FILE="wallet.txt"
# Cấu hình biến
BINARY="republicd"
HOME_DIR="/root/.republicd"
BACKEND="test"
PREFIX="dele_"

# Kiểm tra file đầu vào
if [ ! -f "$INPUT_FILE" ]; then
    echo "Lỗi: Không tìm thấy file $INPUT_FILE"
    exit 1
fi

# Đếm số thứ tự để đặt tên ví
count=1

while IFS= read -r mnemonic || [ -n "$mnemonic" ]; do
    # Bỏ qua dòng trống nếu có
    if [ -z "$mnemonic" ]; then
        continue
    fi

    # Đặt tên ví theo tiền tố và số thứ tự
    WALLET_NAME="${PREFIX}${count}"

    echo "Đang import ví: $WALLET_NAME..."

    # Sử dụng printf để đẩy mnemonic vào lệnh qua pipe
    printf "%s\n" "$mnemonic" | $BINARY keys add "$WALLET_NAME" \
        --home "$HOME_DIR" \
        --keyring-backend "$BACKEND" \
        --recover

    if [ $? -eq 0 ]; then
        echo "✅ Thành công: $WALLET_NAME"
    else
        echo "❌ Thất bại: $WALLET_NAME"
    fi

    echo "-----------------------------------"
    ((count++))

done < "$INPUT_FILE"

echo "Hoàn tất import $(($count-1)) ví."