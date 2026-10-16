    // 1. Khoi tao: Cho phep ngat RX trong ham main
    void uart_init() {
        UART_CTRL_REG = 0x02; // Bat bit 1 (rx_ie = 1)
        enable_global_interrupt();
    }
  
    int main() {
        uart_init();
        while (1) {
            // CPU ranh tay 100% de tinh toan, chop tat LED, xu ly viec khac...
            // KHONG CAN chay while polling ton tai nguyen!
        }
    }
  
    // 2. Trinh phuc vu ngat (ISR - Interrupt Service Routine)
    // Ham nay TU DONG duoc goi khi chan uart_irq bat len 1
    void UART_ISR_Handler(void) {
        uint32_t status = UART_STT_REG; // Doc stt_reg
        
        // Kiem tra co phai ngat do RX khong (bit 1 cua stt_reg)
        if (status & (1 << 1)) {
            uint8_t received_byte = UART_RX_DATA_REG; // Doc 0x004
            
            // Lenh doc 0x004 o tren da TU DONG ha chan uart_irq ve 0!
            process_data(received_byte); // Xu ly du lieu vua nhan
        }
    }