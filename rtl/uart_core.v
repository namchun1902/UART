module uart_core #(
    parameter integer FCLK     = 50000000, // 50 MHz
    parameter integer BAUDRATE = 115200,
    parameter integer OS_TX    = 1,
    parameter integer OS_RX    = 16,
    parameter integer DATA_NUM = 8
)(
    input  wire                clk,
    input  wire                rst_n,

    // Cấu hình khung truyền chung
    input  wire [1:0]          data_bit_num,
    input  wire                stop_bit_num,
    input  wire                parity_en,
    input  wire                parity_type,

    // Giao tiếp TX
    input  wire                start_tx,
    input  wire [DATA_NUM-1:0] tx_data,
    output wire                tx,
    output wire                tx_done,

    // Giao tiếp RX
    input  wire                rx,
    input  wire                clear_rx_done,
    output wire [DATA_NUM-1:0] rx_data,
    output wire                rx_done,
    output wire                parity_error
);

    // Tín hiệu nhịp dùng chung từ bộ sinh Baudrate
    wire tx_tick_last;
    wire rx_tick_last;

    // 1. Khai báo 1 bộ Baudrate Generator duy nhất cho toàn bộ hệ thống
    uart_baudrate #(
        .FCLK(FCLK),
        .BAUDRATE(BAUDRATE),
        .OS_TX(OS_TX),
        .OS_RX(OS_RX)
    ) u_baudrate (
        .clk(clk),
        .rst_n(rst_n),
        .tx_tick_last(tx_tick_last),
        .rx_tick_last(rx_tick_last)
    );

    // 2. Khởi tạo khối UART Transmitter
    uart_tx #(
        .DATA_NUM(DATA_NUM)
    ) u_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_tick_last(tx_tick_last),
        .start_tx(start_tx),
        .tx_data(tx_data),
        .data_bit_num(data_bit_num),
        .stop_bit_num(stop_bit_num),
        .parity_en(parity_en),
        .parity_type(parity_type),
        .tx(tx),
        .tx_done(tx_done)
    );

    // 3. Khởi tạo khối UART Receiver
    uart_rx u_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx_tick_last(rx_tick_last),
        .rx(rx),
        .data_bit_num(data_bit_num),
        .stop_bit_num(stop_bit_num),
        .parity_en(parity_en),
        .parity_type(parity_type),
        .clear_rx_done(clear_rx_done),
        .rx_data(rx_data),
        .rx_done(rx_done),
        .parity_error(parity_error)
    );

endmodule