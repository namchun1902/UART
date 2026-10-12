module uart_rx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        rx_tick_last, // Nhận tick (16x) từ uart_core
    input  wire        rx,
    input  wire [1:0]  data_bit_num,
    input  wire        stop_bit_num,
    input  wire        parity_en,
    input  wire        parity_type,
    input  wire        clear_rx_done,
    output wire [7:0]  rx_data,
    output wire        rx_done,
    output wire        parity_error
);
    wire rx_s, os_mid, os_last, bit_last;
    wire os_clear, os_inc, bit_clear, bit_inc, frame_clear;
    wire sample_en, parity_check, stop_check, latch_en;
    wire frame_error_event;

    uart_rx_controller u_controller (
        .clk(clk), .rst_n(rst_n),
        .rx_s(rx_s), .tick16(rx_tick_last),
        .os_mid(os_mid), .os_last(os_last), .bit_last(bit_last),
        .parity_en(parity_en), .stop_bit_num(stop_bit_num),
        .os_clear(os_clear), .os_inc(os_inc),
        .bit_clear(bit_clear), .bit_inc(bit_inc),
        .frame_clear(frame_clear), .sample_en(sample_en),
        .parity_check(parity_check), .stop_check(stop_check),
        .latch_en(latch_en)
    );

    uart_rx_datapath u_datapath (
        .clk(clk), .rst_n(rst_n),
        .tick16(rx_tick_last),
        .rx(rx), .clear_rx_done(clear_rx_done),
        .data_bit_num(data_bit_num), .parity_type(parity_type),
        .os_clear(os_clear), .os_inc(os_inc),
        .bit_clear(bit_clear), .bit_inc(bit_inc),
        .frame_clear(frame_clear), .sample_en(sample_en),
        .parity_check(parity_check), .stop_check(stop_check),
        .latch_en(latch_en),
        .rx_s(rx_s), .os_mid(os_mid), .os_last(os_last), .bit_last(bit_last),
        .rx_data(rx_data), .rx_done(rx_done), .parity_error(parity_error),
        .frame_error_event(frame_error_event)
    );
endmodule