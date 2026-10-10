module uart_baudrate #(
    parameter integer FCLK     = 50000000, // 50 MHz
    parameter integer BAUDRATE = 115200,
    parameter integer OS_TX    = 1,
    parameter integer OS_RX    = 16
)(
    input  wire clk,
    input  wire rst_n,
    output reg  tx_tick_last,
    output reg  rx_tick_last
);

    // Tính D_RX và ép D_TX = D_RX * OS_RX để triệt tiêu sai số làm tròn số nguyên
    localparam integer D_RX = (FCLK / (OS_RX * BAUDRATE)); 
    localparam integer D_TX = D_RX * OS_RX; 

    localparam integer COUNTER_TX_WIDTH = (D_TX > 1) ? $clog2(D_TX) : 1;
    localparam integer COUNTER_RX_WIDTH = (D_RX > 1) ? $clog2(D_RX) : 1;

    reg [COUNTER_TX_WIDTH-1:0] count_tx;
    reg [COUNTER_RX_WIDTH-1:0] count_rx;

    // Bộ đếm TX chạy tự do
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            count_tx     <= {COUNTER_TX_WIDTH{1'b0}};
            tx_tick_last <= 1'b0;
        end else if (count_tx == D_TX - 1) begin
            count_tx     <= {COUNTER_TX_WIDTH{1'b0}};
            tx_tick_last <= 1'b1;
        end else begin
            count_tx     <= count_tx + 1'b1;
            tx_tick_last <= 1'b0;
        end
    end

    // Bộ đếm RX oversampling 16x chạy tự do
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            count_rx     <= {COUNTER_RX_WIDTH{1'b0}};
            rx_tick_last <= 1'b0;
        end else if (count_rx == D_RX - 1) begin
            count_rx     <= {COUNTER_RX_WIDTH{1'b0}};
            rx_tick_last <= 1'b1;
        end else begin
            count_rx     <= count_rx + 1'b1;
            rx_tick_last <= 1'b0;
        end
    end

endmodule
