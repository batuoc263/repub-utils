#!/bin/bash

# --- Configurations ---
BINARY="republicd"
HOME_DIR="$HOME/.republicd"
KEYRING_BACKEND="test"
CHAIN_ID="raitestnet_77701-1"
RPC_DEFAULT="https://rpc.republicai.io:443"
DENOM="arai"
SERVICE_NAME="republicd"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Helper: Get Balance in RAI
get_bal_rai() {
    local addr=$1
    local bal_arai=$($BINARY query bank balances "$addr" --node "$RPC_DEFAULT" --output json 2>/dev/null | jq -r '.balances[] | select(.denom=="'$DENOM'") | .amount')
    if [ -z "$bal_arai" ]; then bal_arai=0; fi
    echo "scale=4; $bal_arai/1000000000000000000" | bc -l
}

# --- Functions ---

install_node() {
    echo -e "${YELLOW}Installing RepublicAI Node...${NC}"
    # 1. Install Binary (Change URL if version updates)
    wget -O $BINARY https://github.com/republic-ai/republic-mainnet/releases/download/v1.0.0/republicd-linux-amd64
    chmod +x $BINARY
    mv $BINARY /usr/local/bin/
    
    # 2. Init
    $BINARY init "my-node" --chain-id $CHAIN_ID --home $HOME_DIR
    
    # 3. Systemd Service
    sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null <<EOF
[Unit]
Description=Republic AI Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which $BINARY) start --home $HOME_DIR
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    echo -e "${GREEN}Node installed and Service created! Please setup StateSync manually or start service.${NC}"
}

check_status() {
    local catch_up=$($BINARY status --home $HOME_DIR 2>&1 | jq -r '.sync_info.catching_up // .SyncInfo.catching_up')
    local height=$($BINARY status --home $HOME_DIR 2>&1 | jq -r '.sync_info.latest_block_height // .SyncInfo.latest_block_height')
    echo -e "${GREEN}Current Height:${NC} $height"
    if [ "$catch_up" == "false" ]; then
        echo -e "${GREEN}Status:${NC} Fully Synced"
    else
        echo -e "${RED}Status:${NC} Catching up..."
    fi
}

create_wallet() {
    read -p "Enter key name: " kname
    $BINARY keys add "$kname" --keyring-backend $KEYRING_BACKEND --home $HOME_DIR
}

recover_wallet() {
    read -p "Enter key name: " kname
    $BINARY keys add "$kname" --recover --keyring-backend $KEYRING_BACKEND --home $HOME_DIR
}

create_validator() {
    echo -e "${YELLOW}Creating Validator from validator.json...${NC}"
    cat <<EOF > validator.json
{
  "pubkey": $($BINARY comet show-validator --home $HOME_DIR),
  "amount": "100000000000000000arai",
  "moniker": "my-moniker",
  "identity": "",
  "website": "",
  "security": "",
  "details": "Republic AI Validator",
  "commission-rate": "0.1",
  "commission-max-rate": "0.2",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "1"
}
EOF
    echo "Please edit validator.json then press any key to send TX..."
    read -n 1
    $BINARY tx staking create-validator validator.json --from wallet --chain-id $CHAIN_ID --home $HOME_DIR --keyring-backend $KEYRING_BACKEND --gas auto --gas-adjustment 1.5 --fees 100000000000000000arai --node $RPC_DEFAULT -y
}

self_delegate() {
    local addr=$($BINARY keys show wallet -a --keyring-backend $KEYRING_BACKEND --home $HOME_DIR)
    local bal=$(get_bal_rai $addr)
    echo -e "${GREEN}Balance:${NC} $bal RAI"
    read -p "Amount to delegate (RAI): " amount
    local fee=0.1
    echo -e "${YELLOW}Gas Fee will be approx $fee RAI${NC}"
    local stake_arai=$(echo "$amount * 1000000000000000000 / 1" | bc)
    $BINARY tx staking delegate $($BINARY keys show wallet --bech val -a --home $HOME_DIR --keyring-backend $KEYRING_BACKEND) ${stake_arai}arai \
    --from wallet --chain-id $CHAIN_ID --home $HOME_DIR --keyring-backend $KEYRING_BACKEND --gas 300000 --fees 100000000000000000arai --node $RPC_DEFAULT -y
}

create_dele_wallets() {
    read -p "How many wallets (dele_xx): " count
    for ((i=1; i<=count; i++)); do
        suffix=$(printf "%02d" $i)
        $BINARY keys add "dele_$suffix" --keyring-backend $KEYRING_BACKEND --home $HOME_DIR
    done
}

check_dele_balances() {
    printf "%-15s | %-15s\n" "Key" "Balance (RAI)"
    $BINARY keys list --keyring-backend $KEYRING_BACKEND --home $HOME_DIR --output json | jq -r '.[] | select(.name | startswith("dele_")) | .name + ":" + .address' | while read -r line; do
        name=${line%%:*}; addr=${line#*:}; bal=$(get_bal_rai $addr)
        printf "%-15s | %-15s\n" "$name" "$bal"
    done
}

auto_delegate() {
    VAL_ADDR=$($BINARY keys show wallet --bech val -a --home $HOME_DIR --keyring-backend $KEYRING_BACKEND)
    $BINARY keys list --keyring-backend $KEYRING_BACKEND --home $HOME_DIR --output json | jq -r '.[] | select(.name | startswith("dele_")) | .name + ":" + .address' | while read -r line; do
        name=${line%%:*}; addr=${line#*:}; bal=$(get_bal_rai $addr)
        if (( $(echo "$bal > 0.5" | bc -l) )); then
            stake_rai=$(echo "$bal - 0.2" | bc -l)
            stake_arai=$(printf "%.0f" $(echo "$stake_rai * 1000000000000000000" | bc -l))
            $BINARY tx staking delegate $VAL_ADDR ${stake_arai}arai --from $name --chain-id $CHAIN_ID --home $HOME_DIR --keyring-backend $KEYRING_BACKEND --fees 100000000000000000arai --node $RPC_DEFAULT -y
            sleep 5
        fi
    done
}

cleanup() {
    echo -e "${RED}WARNING: This will delete ALL node data and service!${NC}"
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" == "y" ]; then
        systemctl stop $SERVICE_NAME
        systemctl disable $SERVICE_NAME
        rm /etc/systemd/system/$SERVICE_NAME.service
        rm -rf $HOME_DIR
        rm /usr/local/bin/$BINARY
        echo -e "${GREEN}Cleanup finished.${NC}"
    fi
}

# --- Menu ---
while true; do
    echo -e "\n${GREEN}=== RepublicAI Validator Manager ===${NC}"
    echo "1) Install Node (Systemd)"   echo "2) Check Sync Status"
    echo "3) Create Wallet"           echo "4) Recover Wallet"
    echo "5) Create Validator"        echo "6) Self Delegate"
    echo "7) View Logs"               echo "8) Create 'dele_' Wallets"
    echo "9) Check All dele_ Balances" echo "10) Auto Delegate (>0.5 RAI)"
    echo "11) CLEANUP (Delete Node)"   echo "12) Exit"
    read -p "Choose: " choice
    case $choice in
        1) install_node ;;        2) check_status ;;
        3) create_wallet ;;       4) recover_wallet ;;
        5) create_validator ;;    6) self_delegate ;;
        7) journalctl -u $SERVICE_NAME -f -o cat ;;
        8) create_dele_wallets ;; 9) check_dele_balances ;;
        10) auto_delegate ;;      11) cleanup ;;
        12) exit 0 ;;
    esac
done