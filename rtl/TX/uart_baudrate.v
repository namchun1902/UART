module uart_baudrate
    #(  parameter FCLK = 50000000, // 50 MHz
        parameter BAUDRATE = 115200,
        parameter OS_TX = 1, // TX: OS = 1; RX: OS = 16
        parameter OS_RX = 16
    )
    (input  clk,
    input   rst_n,
    output reg tx_tick_last,
    output reg rx_tick_last);

    // Tính giá trị D
    localparam integer D_TX = (FCLK / (OS_TX * BAUDRATE)); // D = round(f_clk / (os*baudreate))
    localparam integer COUNTER_TX_WIDTH = $clog2(D_TX);

    localparam integer D_RX = (FCLK / (OS_RX * BAUDRATE)); 
    localparam integer COUNTER_RX_WIDTH = $clog2(D_RX);

    reg [COUNTER_TX_WIDTH-1:0] count_tx;
    reg [COUNTER_RX_WIDTH-1:0] count_rx;

    // Tin hieu dieu khien TX
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            count_tx <= 0;
            tx_tick_last <= 0;
        end
        else if (count_tx == D_TX - 1) begin
            count_tx <= 0;
            tx_tick_last <= 1'b1;
        end
        else begin
            count_tx <= count_tx + 1'b1;
            tx_tick_last <= 0;
        end
    end

        always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            count_rx <= 0;
            rx_tick_last <= 0;
        end
        else if (count_rx == D_RX - 1) begin
            count_rx <= 0;
            rx_tick_last <= 1'b1;
        end
        else begin
            count_rx <= count_rx + 1'b1;
            rx_tick_last <= 0;
        end
    end

endmodule