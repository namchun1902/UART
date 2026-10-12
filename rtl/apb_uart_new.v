module apb_uart #(
  parameter integer FCLK     = 50000000,    // TAN SO XUNG NHIP HE THONG
  parameter integer BAUDRATE = 115200,      // BAUDRATE mac dinh
  parameter integer OS_TX    = 1,           // Hệ số oversampling cho TX
  parameter integer OS_RX    = 16           // Hệ số oversampling cho RX
) (
  // 1. TIN HIEU TOAN CUC
  input  wire        clk,         // Tin hieu clock he thong cho UART Core
  input  wire        reset_n,     // Reset bat dong bo active low he thong

  // 2. BUS APB
  input  wire        pclk,        // APB clock signal
  input  wire        presetn,     // APB reset signal
  input  wire        psel,        // APB slave select
  input  wire        penable,     // APB enable signal
  input  wire        pwrite,      // 1 = Ghi (wr), 0 = Doc (rd)
  input  wire [3:0]  pstrb,       // Write strobe (ghi theo tung byte)
  input  wire [11:0] paddr,       // APB address bus (12-bit)
  input  wire [31:0] pwdata,      // APB write data (32-bit tu CPU)
  output wire        pready,      // Slave ready signal
  output wire        pslverr,     // Slave transfer error (bao loi dia chi)
  output wire [31:0] prdata,      // APB read data (32-bit gui quay ve CPU)

  // 3. TIN HIEU GIAO TIEP VOI NGOAI VI
  input  wire        rx,          // Chan nhan du lieu noi tiep (serial) tu ngoai vi (PC) vao
  input  wire        cts_n,       // Clear-to-send (Active low, bat tay phan cung)
  output wire        tx,          // Chan truyen du lieu noi tiep ra ngoai vi
  output wire        rts_n        // Request-to-send (Active low, bat tay phan cung)
);

  // I. Tin hieu trung gian giao tiep giua cac khoi
  // 1. Giao tiep giua Interface va UART TX
  wire [7:0] tx_data;             // Du lieu Interface gui sang TX
  wire       start_tx;            // Tin hieu kich hoat truyen tu Interface sang TX
  wire       tx_done;             // Co bao da truyen xong (1 = ranh, 0 = dang ban)

  // 2. Giao tiep giua Interface va UART RX
  wire [7:0] rx_data;             // Du lieu song song do RX nhan duoc gui sang Interface
  wire       rx_done;             // Co bao RX da nhan xong 1 byte du lieu hop le
  wire       parity_error;        // Co bao loi parity khi nhan du lieu
  wire       clear_rx_done;       // Xung tu Interface xoa co rx_done khi CPU doc xong thanh ghi 0x04

  // 3. Tin hieu Interface sang ca TX & RX
  wire [1:0] data_bit_num;        // So luong data bit: 5, 6, 7, 8 bit
  wire       stop_bit_num;        // So luong stop bit: 0 = 1-bit, 1 = 2-bit
  wire       parity_en;           // Cho phep kiem tra parity: 0 = tat, 1 = bat
  wire       parity_type;         // Kieu parity: 0 = Le, 1 = Chan

  // 4. Tin hieu xung chia tan tu Baudrate Generator dung chung
  wire       tx_tick_last;        // Xung nhip truyen cho khoi TX
  wire       rx_tick_last;        // Xung nhip oversampling 16x cho khoi RX


  // II. KHOI TAO CAC MODULE CON
  // 1. Khoi APB Slave Interface (Gom FSM + Datapath Register)
  top_interface_uart_slave apb_interface (
    // Bus APB
    .pclk          ( pclk          ),
    .presetn       ( presetn       ),
    .psel          ( psel          ),
    .penable       ( penable       ),
    .pwrite        ( pwrite        ),
    .paddr         ( paddr         ),
    .pwdata        ( pwdata        ),
    .pstrb         ( pstrb         ),
    .prdata        ( prdata        ),
    .pready        ( pready        ),
    .pslverr       ( pslverr       ),

    // Giao tiep TX
    .tx_data       ( tx_data       ),
    .start_tx      ( start_tx      ),
    .tx_done       ( tx_done       ),

    // Giao tiep RX
    .rx_data       ( rx_data       ),
    .rx_done       ( rx_done       ),
    .parity_error  ( parity_error  ),
    .clear_rx_done ( clear_rx_done ),

    // Cau hinh khung truyen
    .data_bit_num  ( data_bit_num  ),
    .stop_bit_num  ( stop_bit_num  ),
    .parity_en     ( parity_en     ),
    .parity_type   ( parity_type   )
  );

  // 2. Khoi Sinh Baudrate Dung Chung (Single Baudrate Generator)
  uart_baudrate #(
    .FCLK         ( FCLK          ),
    .BAUDRATE     ( BAUDRATE      ),
    .OS_TX        ( OS_TX         ),
    .OS_RX        ( OS_RX         )
  ) u_baudrate (
    .clk          ( clk           ),
    .rst_n        ( reset_n       ),
    .tx_tick_last ( tx_tick_last  ),
    .rx_tick_last ( rx_tick_last  )
  );

  // 3. Khoi Truyen UART (Transmitter)
  uart_tx #(
    .DATA_NUM     ( 8             )
  ) u_uart_tx (
    .clk          ( clk           ),
    .rst_n        ( reset_n       ),
    .tx_tick_last ( tx_tick_last  ),
    .start_tx     ( start_tx      ),
    .tx_data      ( tx_data       ),
    .data_bit_num ( data_bit_num  ),
    .stop_bit_num ( stop_bit_num  ),
    .parity_en    ( parity_en     ),
    .parity_type  ( parity_type   ),
    .tx           ( tx            ),
    .tx_done      ( tx_done       )
  );

  // 4. Khoi Nhan UART (Receiver)
  uart_rx u_uart_rx (
    .clk           ( clk           ),
    .rst_n         ( reset_n       ),
    .rx_tick_last  ( rx_tick_last  ),
    .rx            ( rx            ),
    .data_bit_num  ( data_bit_num  ),
    .stop_bit_num  ( stop_bit_num  ),
    .parity_en     ( parity_en     ),
    .parity_type   ( parity_type   ),
    .clear_rx_done ( clear_rx_done ),
    .rx_data       ( rx_data       ),
    .rx_done       ( rx_done       ),
    .parity_error  ( parity_error  )
  );

  // Bat tay phan cung (RTS luon active low = 0: bao cho ngoai vi biet UART luon san sang nhan)
  assign rts_n = 1'b0;

endmodule