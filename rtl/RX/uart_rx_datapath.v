// UART RX registers, counters, synchronizer and status comparators.
module uart_rx_datapath #(
    parameter integer FCLK = 50000000,
    parameter integer BAUDRATE = 115200
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        rx,
    input  wire [1:0]  data_bit_num,
    input  wire        parity_type,
    input  wire        os_clear, os_inc, bit_clear, bit_inc,
    input  wire        frame_clear, sample_en, parity_check, stop_check, latch_en,
    output reg         rx_s,
    output wire        tick16, os_mid, os_last, bit_last,
    output reg  [8:0]  rx_data,
    output reg         rx_valid, frame_err, parity_err
);
    reg rx_ff1;
    // RX always uses 16x oversampling; the FSM assumes 16 ticks per bit.
    // Use wide arithmetic and a sized counter instead of a 16-bit baud input.
    localparam integer CLKS_PER_BIT = (BAUDRATE > 0) ? FCLK / BAUDRATE : 0;
    localparam integer DIV16 = (CLKS_PER_BIT + 64'd8) / 16;
    localparam integer BAUD_CNT_WIDTH = (DIV16 > 1) ? $clog2(DIV16) : 1;
    reg [BAUD_CNT_WIDTH-1:0] baud_cnt;
    reg [4:0] os_cnt;
    reg [3:0] bit_cnt;
    reg [8:0] sh;
    reg parity_acc;
    wire expected_parity;

    // Round the 16x tick interval as in the previous RX implementation.
    assign tick16 = (baud_cnt == DIV16 - 1);
    // synthesis translate_off
    initial begin
        if (FCLK <= 0 || BAUDRATE <= 0 || CLKS_PER_BIT < 16)
            $fatal(1, "UART RX requires FCLK > 0, BAUDRATE > 0 and FCLK >= 16*BAUDRATE");
    end
    // synthesis translate_on
    assign os_mid = (os_cnt == 5'd7);
    assign os_last = (os_cnt == 5'd15);
    assign bit_last =
        (data_bit_num == 2'b00) ? (bit_cnt == 4'd4) :
        (data_bit_num == 2'b01) ? (bit_cnt == 4'd5) :
        (data_bit_num == 2'b10) ? (bit_cnt == 4'd6) :
                                 (bit_cnt == 4'd7);
    // TX convention: 1 = even parity, 0 = odd parity.
    assign expected_parity = parity_type ? parity_acc : ~parity_acc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_ff1 <= 1'b1;
            rx_s   <= 1'b1;
        end else begin
            rx_ff1 <= rx;
            rx_s   <= rx_ff1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            baud_cnt <= {BAUD_CNT_WIDTH{1'b0}};
        else if (tick16)
            baud_cnt <= {BAUD_CNT_WIDTH{1'b0}};
        else
            baud_cnt <= baud_cnt + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            os_cnt     <= 5'd0;
            bit_cnt    <= 4'd0;
            sh         <= 9'd0;
            parity_acc <= 1'b0;
            rx_data    <= 9'd0;
            rx_valid   <= 1'b0;
            frame_err  <= 1'b0;
            parity_err <= 1'b0;
        end else begin
            // Valid and errors are one-clock pulses, even between ticks.
            rx_valid   <= 1'b0;
            frame_err  <= 1'b0;
            parity_err <= 1'b0;
            if (os_clear)
                os_cnt <= 5'd0;
            else if (os_inc)
                os_cnt <= os_cnt + 5'd1;
            if (bit_clear)
                bit_cnt <= 4'd0;
            else if (bit_inc)
                bit_cnt <= bit_cnt + 4'd1;
            if (frame_clear) begin
                sh         <= 9'd0;
                parity_acc <= 1'b0;
            end else if (sample_en) begin
                sh[bit_cnt] <= rx_s; // UART receives LSB first.
                parity_acc  <= parity_acc ^ rx_s;
            end
            if (parity_check)
                parity_err <= (rx_s != expected_parity);
            if (stop_check)
                frame_err <= !rx_s;
            if (latch_en) begin
                rx_data  <= sh;
                rx_valid <= 1'b1;
            end
        end
    end
endmodule
