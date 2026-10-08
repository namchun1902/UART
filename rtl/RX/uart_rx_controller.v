// UART RX control FSM. Commands take effect on a tick16 edge.
module uart_rx_controller (
    input wire clk, rst_n,
    input wire rx_s, tick16, os_mid, os_last, bit_last,
    input wire parity_en, stop_bit_num,
    output reg os_clear, os_inc, bit_clear, bit_inc,
    output reg frame_clear, sample_en, parity_check, stop_check, latch_en
);
    localparam [2:0] IDLE = 3'd0, START = 3'd1, DATA = 3'd2,
                     PARITY = 3'd3, STOP1 = 3'd4, STOP2 = 3'd5;
    reg [2:0] state, next_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always @* begin
        next_state   = state;
        os_clear     = 1'b0;
        os_inc       = 1'b0;
        bit_clear    = 1'b0;
        bit_inc      = 1'b0;
        frame_clear  = 1'b0;
        sample_en    = 1'b0;
        parity_check = 1'b0;
        stop_check   = 1'b0;
        latch_en     = 1'b0;

        if (tick16) begin
            case (state)
                IDLE: begin
                    os_clear = 1'b1;
                    if (!rx_s)
                        next_state = START;
                end
                START: begin
                    if (!os_mid)
                        os_inc = 1'b1;
                    else begin
                        os_clear = 1'b1;
                        if (rx_s)
                            next_state = IDLE; // False start.
                        else begin
                            bit_clear   = 1'b1;
                            frame_clear = 1'b1;
                            next_state  = DATA;
                        end
                    end
                end
                DATA: begin
                    if (!os_last)
                        os_inc = 1'b1;
                    else begin
                        os_clear  = 1'b1;
                        sample_en = 1'b1;
                        if (bit_last)
                            next_state = parity_en ? PARITY : STOP1;
                        else
                            bit_inc = 1'b1;
                    end
                end
                PARITY: begin
                    if (!os_last)
                        os_inc = 1'b1;
                    else begin
                        os_clear     = 1'b1;
                        parity_check = 1'b1;
                        next_state   = STOP1;
                    end
                end
                STOP1: begin
                    if (!os_last)
                        os_inc = 1'b1;
                    else begin
                        os_clear   = 1'b1;
                        stop_check = 1'b1;
                        if (!rx_s)
                            next_state = IDLE;
                        else if (stop_bit_num)
                            next_state = STOP2;
                        else begin
                            latch_en   = 1'b1;
                            next_state = IDLE;
                        end
                    end
                end
                STOP2: begin
                    if (!os_last)
                        os_inc = 1'b1;
                    else begin
                        os_clear   = 1'b1;
                        stop_check = 1'b1;
                        latch_en   = rx_s;
                        next_state = IDLE;
                    end
                end
                default: begin
                    next_state = IDLE;
                    os_clear   = 1'b1;
                    bit_clear  = 1'b1;
                end
            endcase
        end
    end
endmodule
