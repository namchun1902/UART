module uart_tx #(
    parameter DATA_NUM = 8
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                tx_tick_last, // Nhận tick từ uart_core
    input  wire                start_tx,
    input  wire [DATA_NUM-1:0] tx_data,
    input  wire [1:0]          data_bit_num,
    input  wire                stop_bit_num,
    input  wire                parity_en,
    input  wire                parity_type,
    output wire                tx,
    output wire                tx_done
);
    wire bit_last, stop_last, clr_bit, clr_stop, load_reg, shift_reg;
    wire [1:0] tx_sel;

    tx_fsm_control u_fsm (
        .clk(clk), .rst_n(rst_n),
        .start_tx(start_tx),
        .tick_last(tx_tick_last),
        .bit_last(bit_last), .stop_last(stop_last),
        .parity_en(parity_en),
        .clr_bit(clr_bit), .clr_stop(clr_stop),
        .load_reg(load_reg), .shift_reg(shift_reg),
        .tx_done(tx_done), .tx_sel(tx_sel)
    );

    tx_data_path #(.DATA_NUM(DATA_NUM)) u_datapath (
        .clk(clk), .rst_n(rst_n),
        .tick_last(tx_tick_last),
        .data_bit_num(data_bit_num), .stop_bit_num(stop_bit_num),
        .clr_bit(clr_bit), .clr_stop(clr_stop),
        .load_reg(load_reg), .shift_reg(shift_reg),
        .tx_sel(tx_sel), .tx_data(tx_data),
        .parity_type(parity_type),
        .bit_last(bit_last), .stop_last(stop_last),
        .tx(tx)
    );
endmodule