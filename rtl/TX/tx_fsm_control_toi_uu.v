module tx_fsm_control(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start_tx,    // Tín hiệu pulse từ APB
    input  wire       tick_last,   // tx_tick_last từ uart_baudrate
    input  wire       bit_last,
    input  wire       stop_last,
    input  wire       parity_en,
    output reg        clr_bit,
    output reg        clr_stop,
    output reg        load_reg,
    output reg        shift_reg,
    output reg        tx_done,
    output reg [1:0]  tx_sel
);

    localparam IDLE   = 3'b000,
               START  = 3'b001, 
               DATA   = 3'b010, 
               PARITY = 3'b011, 
               STOP   = 3'b100;

    reg [2:0] state, nxt_state;
    reg       start_pending;

    wire start_req = start_tx || start_pending;

    // Chốt yêu cầu truyền cho đến khi gặp xung tick_last
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            start_pending <= 1'b0;
        end else begin
            if (start_tx) begin
                start_pending <= 1'b1;
            end else if (state == IDLE && start_req && tick_last) begin
                start_pending <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            state <= IDLE;
        else
            state <= nxt_state;
    end 

    always @(*) begin
        nxt_state = state;
        load_reg  = 1'b0;
        shift_reg = 1'b0;

        case(state) 
            IDLE: begin
                // CHỈ nhảy sang START khi có yêu cầu VÀ đúng nhịp tick_last
                if (start_req && tick_last) begin
                    nxt_state = START;
                    load_reg  = 1'b1;
                end
            end
            START: begin
                if (tick_last) begin
                    nxt_state = DATA;
                end
            end
            DATA: begin
                if (!bit_last && tick_last) begin
                    shift_reg = 1'b1;
                end else if (bit_last && tick_last && parity_en) begin
                    nxt_state = PARITY;
                end else if (bit_last && tick_last && !parity_en) begin
                    nxt_state = STOP;
                end
            end
            PARITY: begin
                if (tick_last) begin
                    nxt_state = STOP;
                end
            end
            STOP: begin
                if (stop_last && tick_last) begin
                    nxt_state = IDLE;
                end
            end
            default: nxt_state = IDLE;
        endcase
    end

    always @(*) begin
        tx_done  = 1'b0;
        tx_sel   = 2'b01;
        clr_bit  = 1'b1;
        clr_stop = 1'b1;
        
        case(state) 
            IDLE: begin
                tx_done  = !start_req;
                tx_sel   = 2'b01;
            end
            START: begin
                tx_sel   = 2'b00;
            end
            DATA: begin
                tx_sel   = 2'b10;
                clr_bit  = 1'b0;
            end
            PARITY: begin
                tx_sel   = 2'b11;
            end
            STOP: begin
                tx_sel   = 2'b01;
                clr_stop = 1'b0;
            end
            default: begin
                tx_done  = 1'b1;
                tx_sel   = 2'b01;
            end
        endcase
    end

endmodule
