/**
 * ==============================================================================
 * Project      : APB UART IP Core on Altera/Intel FPGA (Nios II & Nios V Soft-CPUs)
 * File Name    : nios2_uart.c (Tương thích cả Nios II và Nios V/m, V/c, V/g)
 * Description  : Driver C điều khiển UART qua ngắt (Interrupt-Driven).
 *                Hỗ trợ đa nền tảng:
 *                  - Tương thích Nios II truyền thống (__nios2__)
 *                  - Tương thích Nios V kiến trúc RISC-V (__niosv__, __riscv)
 *                  - Khung truyền cấu hình động (5..8 data bits, 1/2 stop, parity)
 *                  - Ngắt nhận RX tự động xóa cờ khi đọc thanh ghi RX_DATA
 *                  - Ngắt phát TX điều khiển theo mức (Level-triggered)
 *                  - Bộ đệm vòng (Ring Buffer / FIFO) cho cả chiều Thu và Phát
 *                  - Khóa ngắt Critical Section chống Race Condition (Xung đột tài nguyên)
 * ==============================================================================
 */

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

// Nios II & Nios V (RISC-V) HAL Headers
#if defined(__nios2__) || defined(__niosv__) || defined(__niosv) || defined(__riscv)
  #include <system.h>
  #include <io.h>
  #include <sys/alt_irq.h>
#else
  // Định nghĩa giả lập khi biên dịch kiểm tra trên môi trường PC/GCC thông thường
  typedef uint32_t alt_irq_context;
  static inline alt_irq_context alt_irq_disable_all(void) { return 0; }
  static inline void alt_irq_enable_all(alt_irq_context ctx) { (void)ctx; }
#endif

// ==============================================================================
// 1. ĐỊNH NGHĨA ĐỊA CHỈ & THANH GHI BỘ ĐIỀU KHIỂN UART (APB REGISTER MAP)
// ==============================================================================

#ifndef UART_BASE
  #ifdef UART_0_BASE
    #define UART_BASE         UART_0_BASE
    #define UART_IRQ          UART_0_IRQ
    #define UART_IRQ_CTRL_ID  UART_0_IRQ_INTERRUPT_CONTROLLER_ID
  #else
    #define UART_BASE         0x00000000
    #define UART_IRQ          0
    #define UART_IRQ_CTRL_ID  0
  #endif
#endif

// Offset các thanh ghi (mỗi thanh ghi 32-bit cách nhau 4 byte)
#define UART_REG_TX_DATA      0x000  // [RW] 0x00: Thanh ghi dữ liệu phát (8-bit)
#define UART_REG_RX_DATA      0x004  // [RO] 0x04: Thanh ghi dữ liệu nhận (8-bit), đọc tự xóa ngắt RX
#define UART_REG_CFG          0x008  // [RW] 0x08: Thanh ghi cấu hình khung truyền
#define UART_REG_CTRL         0x00C  // [RW] 0x0C: Thanh ghi điều khiển (Start TX, Cho phép ngắt)
#define UART_REG_STT          0x010  // [RO] 0x10: Thanh ghi trạng thái (TX Done, RX Done, Parity Error)

// ------------------------------------------------------------------------------
// Bitmask cho thanh ghi cấu hình CFG_REG (0x008)
// ------------------------------------------------------------------------------
#define UART_CFG_DATA_5BIT    (0x00 << 0) // 5 bit dữ liệu
#define UART_CFG_DATA_6BIT    (0x01 << 0) // 6 bit dữ liệu
#define UART_CFG_DATA_7BIT    (0x02 << 0) // 7 bit dữ liệu
#define UART_CFG_DATA_8BIT    (0x03 << 0) // 8 bit dữ liệu (chuẩn phổ biến)

#define UART_CFG_STOP_1BIT    (0x00 << 2) // 1 stop bit
#define UART_CFG_STOP_2BIT    (0x01 << 2) // 2 stop bits

#define UART_CFG_PARITY_DIS   (0x00 << 3) // Tắt kiểm tra Parity (None Parity)
#define UART_CFG_PARITY_EN    (0x01 << 3) // Bật kiểm tra Parity

#define UART_CFG_PARITY_ODD   (0x00 << 4) // Parity Lẻ (Odd)
#define UART_CFG_PARITY_EVEN  (0x01 << 4) // Parity Chẵn (Even)

// Các cấu hình khung thông dụng:
#define UART_CFG_8N1          (UART_CFG_DATA_8BIT | UART_CFG_STOP_1BIT | UART_CFG_PARITY_DIS)
#define UART_CFG_8E1          (UART_CFG_DATA_8BIT | UART_CFG_STOP_1BIT | UART_CFG_PARITY_EN | UART_CFG_PARITY_EVEN)
#define UART_CFG_8O1          (UART_CFG_DATA_8BIT | UART_CFG_STOP_1BIT | UART_CFG_PARITY_EN | UART_CFG_PARITY_ODD)

// ------------------------------------------------------------------------------
// Bitmask cho thanh ghi điều khiển CTRL_REG (0x00C)
// ------------------------------------------------------------------------------
#define UART_CTRL_START_TX    (1 << 0)    // Bit 0: Ghi 1 kích hoạt phát 1 byte (tự xóa về 0 sau 1 clock)
#define UART_CTRL_RX_IE       (1 << 1)    // Bit 1: 1 = Cho phép ngắt khi có byte nhận đến (RX Interrupt)
#define UART_CTRL_TX_IE       (1 << 2)    // Bit 2: 1 = Cho phép ngắt khi bộ phát rảnh/truyền xong (TX Interrupt)

// ------------------------------------------------------------------------------
// Bitmask cho thanh ghi trạng thái STT_REG (0x010)
// ------------------------------------------------------------------------------
#define UART_STT_TX_DONE      (1 << 0)    // Bit 0: 1 = Bộ phát rảnh / vừa truyền xong
#define UART_STT_RX_DONE      (1 << 1)    // Bit 1: 1 = Bộ thu có byte dữ liệu mới chưa đọc
#define UART_STT_PARITY_ERR   (1 << 2)    // Bit 2: 1 = Phát hiện lỗi Parity ở byte vừa nhận

// ==============================================================================
// 2. MACRO TRUY XUẤT PHẦN CỨNG (I/O ACCESS)
// ==============================================================================

#if defined(__nios2__) || defined(__niosv__) || defined(__niosv) || defined(__riscv)
  #define HW_READ_32(base, offset)        IORD_32DIRECT((base), (offset))
  #define HW_WRITE_32(base, offset, val)  IOWR_32DIRECT((base), (offset), (val))
#else
  #define HW_READ_32(base, offset)        (*(volatile uint32_t *)((uintptr_t)((base) + (offset))))
  #define HW_WRITE_32(base, offset, val)  (*(volatile uint32_t *)((uintptr_t)((base) + (offset))) = (uint32_t)(val))
#endif

// ==============================================================================
// 3. CẤU TRÚC BỘ ĐỆM VÒNG (CIRCULAR RING BUFFER) CHO TX VÀ RX
// ==============================================================================

#define UART_RX_BUF_SIZE  128
#define UART_TX_BUF_SIZE  128

typedef struct {
    uint8_t buffer[UART_RX_BUF_SIZE];
    volatile uint16_t head;
    volatile uint16_t tail;
} RingBuffer_RX;

typedef struct {
    uint8_t buffer[UART_TX_BUF_SIZE];
    volatile uint16_t head;
    volatile uint16_t tail;
} RingBuffer_TX;

static RingBuffer_RX g_rx_buf = {{0}, 0, 0};
static RingBuffer_TX g_tx_buf = {{0}, 0, 0};

// Biến lưu trạng thái thanh ghi điều khiển hiện tại
static volatile uint32_t g_ctrl_mirror = 0;
static volatile uint32_t g_parity_error_count = 0;

// ==============================================================================
// 4. CÁC HÀM XỬ LÝ BỘ ĐỆM VÒNG (RING BUFFER HELPERS)
// ==============================================================================

static inline bool rx_buf_is_empty(void) {
    return (g_rx_buf.head == g_rx_buf.tail);
}

static inline bool rx_buf_is_full(void) {
    return (((g_rx_buf.head + 1) % UART_RX_BUF_SIZE) == g_rx_buf.tail);
}

static inline void rx_buf_put(uint8_t byte) {
    if (!rx_buf_is_full()) {
        g_rx_buf.buffer[g_rx_buf.head] = byte;
        g_rx_buf.head = (g_rx_buf.head + 1) % UART_RX_BUF_SIZE;
    }
}

static inline bool rx_buf_get(uint8_t *byte) {
    if (rx_buf_is_empty()) return false;
    *byte = g_rx_buf.buffer[g_rx_buf.tail];
    g_rx_buf.tail = (g_rx_buf.tail + 1) % UART_RX_BUF_SIZE;
    return true;
}

static inline bool tx_buf_is_empty(void) {
    return (g_tx_buf.head == g_tx_buf.tail);
}

static inline bool tx_buf_is_full(void) {
    return (((g_tx_buf.head + 1) % UART_TX_BUF_SIZE) == g_tx_buf.tail);
}

static inline void tx_buf_put(uint8_t byte) {
    g_tx_buf.buffer[g_tx_buf.head] = byte;
    g_tx_buf.head = (g_tx_buf.head + 1) % UART_TX_BUF_SIZE;
}

static inline bool tx_buf_get(uint8_t *byte) {
    if (tx_buf_is_empty()) return false;
    *byte = g_tx_buf.buffer[g_tx_buf.tail];
    g_tx_buf.tail = (g_tx_buf.tail + 1) % UART_TX_BUF_SIZE;
    return true;
}

// ==============================================================================
// 5. TRÌNH PHỤC VỤ NGẮT (ISR - INTERRUPT SERVICE ROUTINE)
// ==============================================================================
/**
 * @brief  Hàm ngắt được gọi tự động mỗi khi chân uart_irq nhảy lên mức cao (1).
 * @param  context: Con trỏ ngữ cảnh do Nios II HAL truyền vào (địa chỉ base).
 */
#if defined(__nios2__) || defined(__niosv__) || defined(__niosv) || defined(__riscv)
static void uart_isr_handler(void *context)
#else
void uart_isr_handler(void *context)
#endif
{
    uintptr_t base = (uintptr_t)context;

    // Đọc thanh ghi trạng thái STT_REG (0x010)
    uint32_t status = HW_READ_32(base, UART_REG_STT);

    // --------------------------------------------------------------------------
    // NHÁNH 1: XỬ LÝ NGẮT NHẬN DỮ LIỆU (RX INTERRUPT)
    // --------------------------------------------------------------------------
    if (status & UART_STT_RX_DONE) {
        if (status & UART_STT_PARITY_ERR) {
            g_parity_error_count++;
        }

        // Đọc byte dữ liệu từ RX_DATA_REG (0x004)
        // [LƯU Ý]: Đọc thanh ghi này sẽ tự động kích hoạt clear_rx_done
        // trong phần cứng, hạ cờ rx_done và hạ chân uart_irq về 0.
        uint8_t rx_byte = (uint8_t)(HW_READ_32(base, UART_REG_RX_DATA) & 0xFF);
        rx_buf_put(rx_byte);
    }

    // --------------------------------------------------------------------------
    // NHÁNH 2: XỬ LÝ NGẮT TRUYỀN DỮ LIỆU (TX INTERRUPT)
    // [QUAN TRỌNG]: Chỉ xử lý khi tx_done=1 VÀ phần mềm ĐANG CHO PHÉP ngắt TX (tx_ie=1)
    // --------------------------------------------------------------------------
    if ((status & UART_STT_TX_DONE) && (g_ctrl_mirror & UART_CTRL_TX_IE)) {
        uint8_t next_tx_byte;
        if (tx_buf_get(&next_tx_byte)) {
            // Còn dữ liệu trong Ring Buffer: Nạp byte mới vào TX_DATA_REG (0x000)
            HW_WRITE_32(base, UART_REG_TX_DATA, next_tx_byte);

            // Bật start_tx = 1 để kích phát, bảo toàn trạng thái ngắt hiện tại
            g_ctrl_mirror |= (UART_CTRL_START_TX | UART_CTRL_TX_IE);
            HW_WRITE_32(base, UART_REG_CTRL, g_ctrl_mirror);
            
            // start_tx tự xóa sau 1 clock trong phần cứng
            g_ctrl_mirror &= ~UART_CTRL_START_TX;
        } else {
            // Đã truyền xong toàn bộ dữ liệu trong bộ đệm:
            // TẮT tx_ie = 0 để hạ chân ngắt uart_irq về 0, giữ nguyên rx_ie
            g_ctrl_mirror &= ~UART_CTRL_TX_IE;
            HW_WRITE_32(base, UART_REG_CTRL, g_ctrl_mirror);
        }
    }
}

// ==============================================================================
// 6. CÁC HÀM GIAO TIẾP VỚI DRIVER (API)
// ==============================================================================

/**
 * @brief  Khởi tạo bộ UART và đăng ký ngắt với Nios II / Nios V HAL.
 * @param  base_addr: Địa chỉ cơ sở của APB UART (ví dụ UART_0_BASE).
 * @param  cfg_val  : Cấu hình khung (UART_CFG_8N1, UART_CFG_8E1,...).
 */
void uart_init(uintptr_t base_addr, uint32_t cfg_val)
{
    g_rx_buf.head = g_rx_buf.tail = 0;
    g_tx_buf.head = g_tx_buf.tail = 0;
    g_parity_error_count = 0;

    // Cấu hình khung truyền vào CFG_REG (0x008)
    HW_WRITE_32(base_addr, UART_REG_CFG, cfg_val);

    // Cấu hình mặc định: start_tx = 0, rx_ie = 1, tx_ie = 0
    g_ctrl_mirror = UART_CTRL_RX_IE;
    HW_WRITE_32(base_addr, UART_REG_CTRL, g_ctrl_mirror);

    // Đăng ký hàm ngắt với Interrupt Controller (HAL Nios II & Nios V)
#if defined(__nios2__) || defined(__niosv__) || defined(__niosv) || defined(__riscv)
  #ifdef ALT_ENHANCED_INTERRUPT_API_PRESENT
    alt_ic_isr_register(UART_IRQ_CTRL_ID, UART_IRQ, uart_isr_handler, (void *)base_addr, NULL);
    alt_ic_irq_enable(UART_IRQ_CTRL_ID, UART_IRQ);
  #else
    alt_irq_register(UART_IRQ, (void *)base_addr, uart_isr_handler);
  #endif
#endif
}

/**
 * @brief  Gửi 1 ký tự qua UART sử dụng ngắt và bảo vệ Critical Section.
 * @param  base_addr: Địa chỉ cơ sở UART.
 * @param  c: Ký tự cần truyền.
 */
void uart_putchar(uintptr_t base_addr, char c)
{
    // Chờ cho đến khi bộ đệm phát còn chỗ trống
    while (tx_buf_is_full()) {
        // Chờ buffer được giải phóng bởi ISR
    }

    // KHÓA NGẮT (Critical Section) để bảo vệ g_ctrl_mirror và Ring Buffer
    // Tránh tình trạng ISR can thiệp giữa chừng làm kẹt truyền
    alt_irq_context cpu_sr = alt_irq_disable_all();

    // Đẩy byte vào bộ đệm phát
    tx_buf_put((uint8_t)c);

    // Nếu ngắt TX đang tắt (bộ phát rảnh, chưa có luồng phát chạy nền)
    if (!(g_ctrl_mirror & UART_CTRL_TX_IE)) {
        // Bật tx_ie = 1. Vì phần cứng đang rảnh (tx_done = 1),
        // ngay sau khi mở lại ngắt, phần cứng sẽ kích hoạt ISR để lấy byte ra phát
        g_ctrl_mirror |= UART_CTRL_TX_IE;
        HW_WRITE_32(base_addr, UART_REG_CTRL, g_ctrl_mirror);
    }

    // MỞ LẠI NGẮT
    alt_irq_enable_all(cpu_sr);
}

/**
 * @brief  Gửi một chuỗi ký tự qua UART.
 * @param  base_addr: Địa chỉ cơ sở UART.
 * @param  str: Chuỗi ký tự kết thúc bằng '\0'.
 */
void uart_puts(uintptr_t base_addr, const char *str)
{
    while (*str) {
        uart_putchar(base_addr, *str++);
    }
}

/**
 * @brief  Đọc 1 ký tự từ bộ đệm nhận (Non-blocking, bảo vệ Critical Section).
 * @param  c: Con trỏ lưu ký tự nhận được.
 * @return true nếu có ký tự mới, false nếu bộ đệm rỗng.
 */
bool uart_getchar(char *c)
{
    alt_irq_context cpu_sr = alt_irq_disable_all();

    uint8_t byte;
    bool has_char = rx_buf_get(&byte);
    if (has_char) {
        *c = (char)byte;
    }

    alt_irq_enable_all(cpu_sr);
    return has_char;
}

/**
 * @brief  Kiểm tra xem có dữ liệu trong bộ đệm nhận hay không.
 */
bool uart_has_data(void)
{
    return !rx_buf_is_empty();
}

/**
 * @brief  Lấy tổng số lỗi Parity đã ghi nhận từ lúc khởi động.
 */
uint32_t uart_get_parity_errors(void)
{
    return g_parity_error_count;
}

// ==============================================================================
// 7. CHƯƠNG TRÌNH CHÍNH MINH HỌA (DEMO MAIN APPLICATION)
// ==============================================================================

int main(void)
{
    uintptr_t uart_base = (uintptr_t)UART_BASE;

    // 1. Khởi tạo UART: Cấu hình 8 bit data, 1 stop bit, không Parity (8N1)
    uart_init(uart_base, UART_CFG_8N1);

    // 2. Gửi thông báo chào mừng ra PC Terminal
    uart_puts(uart_base, "\r\n==============================================\r\n");
    uart_puts(uart_base, "    KHOI DONG APB UART (NIOS II & NIOS V/m)   \r\n");
    uart_puts(uart_base, "     Che do: NGAT TOAN PHAN (RX_IE & TX_IE)   \r\n");
    uart_puts(uart_base, "==============================================\r\n");
    uart_puts(uart_base, "Nhap ky tu tu ban phim de ECHO lai:\r\n");

    // 3. Vòng lặp chính: CPU hoàn toàn rảnh tay xử lý các tác vụ khác
    while (1) {
        char rx_char;

        // Nếu ngắt RX đã nhận được ký tự và đưa vào Ring Buffer
        if (uart_getchar(&rx_char)) {
            // Echo lại ký tự đó
            uart_puts(uart_base, "[Echo]: ");
            uart_putchar(uart_base, rx_char);
            uart_puts(uart_base, "\r\n");
        }

        // CPU có thể chớp tắt LED, tính toán, xử lý logic...
    }

    return 0;
}
