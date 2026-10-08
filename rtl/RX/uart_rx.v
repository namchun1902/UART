// UART RX top: configuration encoding matches uart_tx.
module uart_rx #(
    parameter integer FCLK = 50000000,
    parameter integer BAUDRATE = 115200
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        rx,
    input  wire [1:0]  data_bit_num, // 00: 5, 01: 6, 10: 7, 11: 8 bits
    input  wire        stop_bit_num, // 0: 1 stop, 1: 2 stops
    input  wire        parity_en,
    input  wire        parity_type,  // 1: even, 0: odd (same as TX)
    output wire [8:0]  rx_data,      // Bits above configured length are zero.
    output wire        rx_valid,
    output wire        frame_err,
    output wire        parity_err
);
    // Datapath status -> controller.
    wire rx_s, tick16, os_mid, os_last, bit_last;
    // Controller commands -> datapath (qualified by tick16).
    wire os_clear, os_inc, bit_clear, bit_inc, frame_clear;
    wire sample_en, parity_check, stop_check, latch_en;

    uart_rx_controller u_controller (
        .clk(clk), .rst_n(rst_n),
        .rx_s(rx_s), .tick16(tick16),
        .os_mid(os_mid), .os_last(os_last), .bit_last(bit_last),
        .parity_en(parity_en), .stop_bit_num(stop_bit_num),
        .os_clear(os_clear), .os_inc(os_inc),
        .bit_clear(bit_clear), .bit_inc(bit_inc),
        .frame_clear(frame_clear), .sample_en(sample_en),
        .parity_check(parity_check), .stop_check(stop_check),
        .latch_en(latch_en)
    );

    uart_rx_datapath #(
        .FCLK(FCLK), .BAUDRATE(BAUDRATE)
    ) u_datapath (
        .clk(clk), .rst_n(rst_n), .rx(rx),
        .data_bit_num(data_bit_num), .parity_type(parity_type),
        .os_clear(os_clear), .os_inc(os_inc),
        .bit_clear(bit_clear), .bit_inc(bit_inc),
        .frame_clear(frame_clear), .sample_en(sample_en),
        .parity_check(parity_check), .stop_check(stop_check),
        .latch_en(latch_en),
        .rx_s(rx_s), .tick16(tick16),
        .os_mid(os_mid), .os_last(os_last), .bit_last(bit_last),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .frame_err(frame_err), .parity_err(parity_err)
    );
endmodule
