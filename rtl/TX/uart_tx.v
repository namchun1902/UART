module uart_tx #(
    // Tham số hệ thống có thể tùy chỉnh khi gọi module
    parameter FCLK     = 50000000, // Tần số xung nhịp hệ thống (Mặc định 50 MHz)
    parameter BAUDRATE = 115200,   // Tốc độ truyền (Mặc định 115200 bps)
    parameter OS_TX       = 1,        // Hệ số lấy mẫu (TX thường dùng OS = 1)
    parameter OS_RX       = 16,
    parameter DATA_NUM = 8         // Độ rộng bus dữ liệu tối đa
)(
    input  wire                clk,
    input  wire                rst_n,
    
    // Tín hiệu giao tiếp với hệ thống truyền dữ liệu
    input  wire                start_tx, // Kích hoạt truyền
    input  wire [DATA_NUM-1:0] tx_data,  // Dữ liệu cần truyền
    
    // Cấu hình khung truyền (Nhận từ thanh ghi của APB)
    input  wire [1:0]          data_bit_num,    // 00: 5b, 01: 6b, 10: 7b, 11: 8b
    input  wire                stop_bit_num,    // 0: 1 stop bit, 1: 2 stop bits
    input  wire                parity_en,   // 1: Bật parity, 0: Tắt parity
    input  wire                parity_type, // 1: Chẵn (Even), 0: Lẻ (Odd)
    
    // Tín hiệu ngõ ra vật lý
    output wire                tx,       // Chân truyền dữ liệu nối tiếp
    output wire                tx_done   // Cờ báo hiệu hoàn thành 1 khung
);

    //---------------------------------------------------------
    // Khai báo các đường dây nội bộ (Internal Wires)
    //---------------------------------------------------------
    wire       tx_tick_last;
    wire       rx_tick_last;
    wire       bit_last;
    wire       stop_last;
    wire       clr_bit;
    wire       clr_stop;
    wire       load_reg;
    wire       shift_reg;
    wire [1:0] tx_sel;

    //---------------------------------------------------------
    // 1. Khởi tạo Khối chia tần số (Baudrate Generator)
    //---------------------------------------------------------
    uart_baudrate #(
        .FCLK(FCLK),
        .BAUDRATE(BAUDRATE),
        .OS_TX(OS_TX),
        .OS_RX(OS_RX)
    ) u_baudrate (
        .clk(clk),
        .rst_n(rst_n),
        .tx_tick_last(tx_tick_last),
        .rx_tick_last(rx_tick_last)
    );

    //---------------------------------------------------------
    // 2. Khởi tạo Máy trạng thái điều khiển (FSM Control)
    //---------------------------------------------------------
    tx_fsm_control u_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .start_tx(start_tx),
        .tick_last(tx_tick_last),
        .bit_last(bit_last),  
        .stop_last(stop_last),
        .parity_en(parity_en),
        .clr_bit(clr_bit),    
        .clr_stop(clr_stop),  
        .load_reg(load_reg),  
        .shift_reg(shift_reg),
        .tx_done(tx_done),    
        .tx_sel(tx_sel)       
    );

    //---------------------------------------------------------
    // 3. Khởi tạo Đường truyền dữ liệu (Datapath)
    //---------------------------------------------------------
    tx_data_path #(
        .DATA_NUM(DATA_NUM)
    ) u_datapath (
        .clk(clk),
        .rst_n(rst_n),
        .tick_last(tx_tick_last),
        .data_bit_num(data_bit_num),  
        .stop_bit_num(stop_bit_num),  
        .clr_bit(clr_bit),    
        .clr_stop(clr_stop),  
        .load_reg(load_reg),  
        .shift_reg(shift_reg),
        .tx_sel(tx_sel),      
        .tx_data(tx_data),    
        .parity_type(parity_type),
        .bit_last(bit_last),  
        .stop_last(stop_last),
        .tx(tx)               
    );

endmodule