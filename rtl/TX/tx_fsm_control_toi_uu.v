module tx_fsm_control(
    input clk,
    input rst_n,
    input start_tx, // Tín hiệu bắt đầu máy trạng thái FSM
    input tick_last, // Tín hiệu từ uart_baudrate
    input bit_last, // Tín hiệu đếm xong số lượng data_bit
    input stop_last, // Tín hiệu đếm xong số lượng stop bit
    input parity_en, // Tín hiệu thông báo là có tín hiệu parity
    output reg clr_bit, // Reset bộ đếm data_bit
    output reg clr_stop, // Reset bộ đếm stop_bit
    output reg load_reg, // Tín hiệu load dữ liệu tx_data từ apb vào thanh ghi
    output reg shift_reg, // Tín hiệu dịch dữ liệu
    output reg tx_done, // Tín hiệu thông báo hoàn thành
    output reg [1:0] tx_sel // Tín hiệu lựa chọn tín hiệu được đưa ra: start_bit; data_bit; parity; stop_bit
);

    localparam IDLE   = 3'b000,
               START  = 3'b001, 
               DATA   = 3'b010, 
               PARITY = 3'b011, 
               STOP   = 3'b100;

    reg [2:0] state, nxt_state;

    // 1. Khối Sequential: Cập nhật trạng thái
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            state <= IDLE;
        end
        else begin
            state <= nxt_state;
        end
    end 

    // 2. Khối Tổ hợp (Next State & Mealy Outputs)
    always @(start_tx or tick_last or bit_last or stop_last or parity_en or state) begin
        // DEFAULT ASSIGNMENTS
        nxt_state = state;
        load_reg  = 1'b0;
        shift_reg = 1'b0;

        case(state) 
            IDLE: begin
                //if(start_tx && tick_last) begin // Có cần tick_last không?
                if(start_tx) begin
                    nxt_state = START;
                    load_reg  = 1'b1;
                end
            end
            START: begin
                if(tick_last) begin
                    nxt_state = DATA;
                end
            end
            DATA: begin
                if(!bit_last && tick_last) begin
                    shift_reg = 1'b1;
                    // nxt_state = DATA;
                end
                else if(bit_last && tick_last && parity_en) begin
                    nxt_state = PARITY;
                end
                else if(bit_last && tick_last && !parity_en) begin
                    nxt_state = STOP;
                end
            end
            PARITY: begin
                if(tick_last) begin
                    nxt_state = STOP;
                end
            end
            STOP: begin
                if(stop_last && tick_last) begin
                    nxt_state = IDLE;
                end
                // !stop_last && tick_last tự động giữ trạng thái STOP nhờ default
            end
            default: nxt_state = IDLE;
        endcase
    end

    // 3. Khối Tổ hợp (Moore Outputs)
    always @(state) begin
        // DEFAULT ASSIGNMENTS
        tx_done  = 1'b0;
        tx_sel   = 2'b01;
        clr_bit  = 1'b1;
        clr_stop = 1'b1;
        
        case(state) 
            IDLE: begin
                tx_done  = 1'b1;
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