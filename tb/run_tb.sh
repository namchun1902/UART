#!/bin/bash
# ==============================================================================
# Script chay mo phong testbench cho he thong APB UART
# Cach su dung:
#   ./tb/run_tb.sh          -> Chay testbench chinh cho toan he thong (tb_apb_uart.v)
#   ./tb/run_tb.sh edge     -> Chay testbench 6 edge cases chuyen sau (tb_apb_uart_edge_cases.v)
#   ./tb/run_tb.sh inter    -> Chay testbench rieng khoi APB Interface (tb_top_interface_uart_slave.v)
#   ./tb/run_tb.sh new      -> Chay kien truc moi toi uu dung chung Baudrate
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "=========================================================="
echo "          CHAY MO PHONG HE THONG APB UART"
echo "=========================================================="

MODE="${1:-top}"

# Danh sach file co ban
RTL_INTER="rtl/interface_uart/uart_apb_fsm.v rtl/interface_uart/apb_datapath.v rtl/interface_uart/top_interface_uart_slave.v"
RTL_TX_CORE="rtl/TX/uart_baudrate.v rtl/TX/tx_fsm_control_toi_uu.v rtl/TX/tx_data_path_toi_uu.v"
RTL_RX_CTRL="rtl/RX/uart_rx_controller.v"

case "$MODE" in
  inter|interface)
    echo "[INFO] Che do: Testbench rieng cho APB Interface"
    TOP_MODULE="tb_top_interface_uart_slave"
    FILES="$RTL_INTER tb/tb_top_interface_uart_slave.v"
    ;;
  edge|system_edge)
    echo "[INFO] Che do: Testbench 6 EDGE CASES he thong APB UART"
    TOP_MODULE="tb_apb_uart_edge_cases"
    FILES="$RTL_INTER $RTL_TX_CORE rtl/TX/uart_tx.v $RTL_RX_CTRL rtl/RX/uart_rx_datapath.v rtl/RX/uart_rx.v rtl/apb_uart.v tb/tb_apb_uart_edge_cases.v"
    ;;
  new|optimized)
    echo "[INFO] Che do: Testbench KIEN TRUC MOI TOI UU (Single Baudrate Generator)"
    TOP_MODULE="tb_apb_uart"
    FILES="$RTL_INTER $RTL_TX_CORE rtl/TX/uart_tx_new.v $RTL_RX_CTRL rtl/RX/uart_rx_datapath_new.v rtl/RX/uart_rx_new.v rtl/uart_core.v rtl/apb_uart_new.v tb/tb_apb_uart.v"
    ;;
  top|*)
    echo "[INFO] Che do: Testbench TOAN BO HE THONG APB UART (Default)"
    TOP_MODULE="tb_apb_uart"
    FILES="$RTL_INTER $RTL_TX_CORE rtl/TX/uart_tx.v $RTL_RX_CTRL rtl/RX/uart_rx_datapath.v rtl/RX/uart_rx.v rtl/apb_uart.v tb/tb_apb_uart.v"
    ;;
esac

# 1. Uu tien Icarus Verilog neu da cai dat (nhe, chay truc tiep tren terminal)
if command -v iverilog &> /dev/null; then
    echo "[INFO] Bien dich bang Icarus Verilog (iverilog)..."
    iverilog -g2012 -o sim_out $FILES
    echo "[INFO] Ket qua mo phong:"
    echo "----------------------------------------------------------"
    vvp sim_out
    rm -f sim_out
    echo "----------------------------------------------------------"
    echo "[SUCCESS] Mo phong hoan tat bang iverilog!"
# 2. Neu chua co iverilog, kiem tra QuestaSim
elif [ -x /home/numb/Downloads/altera_lite/25.1std/questa_fse/bin/vlog ]; then
    Q_BIN="/home/numb/Downloads/altera_lite/25.1std/questa_fse/bin"
    echo "[INFO] Kiem tra cu phap bang QuestaSim Compiler (vlog)..."
    [ ! -d "work" ] && $Q_BIN/vlib work 2>/dev/null || true
    $Q_BIN/vlog -work work $FILES
    echo ""
    echo "[SUCCESS] Bien dich cu phap thanh cong: 0 Errors, 0 Warnings!"
    echo ""
    
    # Kiem tra xem vsim co chay duoc khong hay bi loi thieu libXft
    if $Q_BIN/vsim -c -do "quit -f" &>/dev/null; then
        echo "[INFO] Dang chay mo phong bang QuestaSim vsim..."
        $Q_BIN/vsim -c -do "run -all; quit -f" "work.$TOP_MODULE"
    else
        echo "=========================================================="
        echo "[CHU Y] De chay simulation xem ket qua in ra man hinh:"
        echo "  Cach 1 (Khuyen dung, nhe va nhanh):"
        echo "      sudo apt update && sudo apt install -y iverilog"
        echo "      Sau do chay lai: ./tb/run_tb.sh"
        echo ""
        echo "  Cach 2 (Chay bang QuestaSim):"
        echo "      sudo apt update && sudo apt install -y libxft2"
        echo "=========================================================="
    fi
else
    echo "[ERROR] Chua tim thay trinh bien dich. Vui long cai dat iverilog:"
    echo "  sudo apt install -y iverilog"
fi
