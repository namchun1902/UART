// UART RX registers, counters, synchronizer and status comparators.
module uart_rx_datapath (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tick16,        // Nhận xung 16x oversampling từ uart_baudrate
    input  wire        rx,
    input  wire        clear_rx_done,
    input  wire [1:0]  data_bit_num,
    input  wire        parity_type,
    input  wire        os_clear, os_inc, bit_clear, bit_inc,
    input  wire        frame_clear, sample_en, parity_check, stop_check, latch_en,
    output reg         rx_s,
    output wire        os_mid, os_last, bit_last,
    output reg  [7:0]  rx_data,
    output reg         rx_done, parity_error,
    output reg         frame_error_event
);
    reg rx_ff1;
    reg [4:0] os_cnt;
    reg [3:0] bit_cnt;
    reg [7:0] sh;
    reg parity_acc;
    reg frame_parity_error;
    wire expected_parity;

    assign os_mid  = (os_cnt == 5'd7);
    assign os_last = (os_cnt == 5'd15);
    assign bit_last =
        (data_bit_num == 2'b00) ? (bit_cnt == 4'd4) :
        (data_bit_num == 2'b01) ? (bit_cnt == 4'd5) :
        (data_bit_num == 2'b10) ? (bit_cnt == 4'd6) :
                                 (bit_cnt == 4'd7);
    
    // Quy ước Parity: 1 = chẵn (even), 0 = lẻ (odd)
    assign expected_parity = parity_type ? parity_acc : ~parity_acc;

    // Khối đồng bộ tín hiệu RX vào clock hệ thống
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_ff1 <= 1'b1;
            rx_s   <= 1'b1;
        end else begin
            rx_ff1 <= rx;
            rx_s   <= rx_ff1;
        end
    end

    // Khối cập nhật bộ đếm và thanh ghi dữ liệu
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            os_cnt             <= 5'd0;
            bit_cnt            <= 4'd0;
            sh                 <= 8'd0;
            parity_acc         <= 1'b0;
            frame_parity_error <= 1'b0;
            rx_data            <= 8'd0;
            rx_done            <= 1'b0;
            parity_error       <= 1'b0;
            frame_error_event  <= 1'b0;
        end else begin
            frame_error_event <= 1'b0;

            if (clear_rx_done) begin
                rx_done      <= 1'b0;
                parity_error <= 1'b0;
            end

            if (os_clear)
                os_cnt <= 5'd0;
            else if (os_inc)
                os_cnt <= os_cnt + 5'd1;

            if (bit_clear)
                bit_cnt <= 4'd0;
            else if (bit_inc)
                bit_cnt <= bit_cnt + 4'd1;

            if (frame_clear) begin
                sh                 <= 8'd0;
                parity_acc         <= 1'b0;
                frame_parity_error <= 1'b0;
            end else if (sample_en) begin
                sh[bit_cnt] <= rx_s; // LSB nhận trước
                parity_acc  <= parity_acc ^ rx_s;
            end

            if (parity_check)
                frame_parity_error <= (rx_s != expected_parity);

            if (stop_check)
                frame_error_event <= !rx_s;

            if (latch_en && (!rx_done || clear_rx_done)) begin
                rx_data      <= sh;
                rx_done      <= 1'b1;
                parity_error <= frame_parity_error;
            end
        end
    end
endmodule