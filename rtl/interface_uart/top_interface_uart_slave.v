module uart_apb_slave_top (
  // Tu APB Bus
  input  wire        pclk,
  input  wire        presetn,
  input  wire        psel,
  input  wire        penable,
  input  wire        pwrite,
  input  wire [11:0] paddr,
  input  wire [31:0] pwdata,
  input  wire [3:0]  pstrb,
  output wire [31:0] prdata,
  output wire        pready,
  output wire        pslverr,

  // Giao tiep voi TX
  output wire [7:0] tx_data,
  output wire       start_tx,
  input  wire       tx_done,

  // Giao tiep voi RX
  input  wire [7:0] rx_data,
  input  wire       rx_done,
  input  wire       parity_error,
  output wire       clear_rx_done,
  
  // Config chung cho ca TX & RX
  output wire [1:0] data_bit_num,
  output wire       stop_bit_num,
  output wire       parity_en,
  output wire       parity_type       // 0 = 1-bit, 1 = 2-bit
);

  // Day noi bo tu FSM -> Datapath
  wire reg_wr_en;
  wire reg_rd_en;
  wire addr_match;

  uart_apb_fsm fsm (
    .pclk       ( pclk       ),
    .presetn    ( presetn    ),
    .psel       ( psel       ),
    .penable    ( penable    ),
    .pwrite     ( pwrite     ),
    .addr_match ( addr_match ),
    .reg_wr_en  ( reg_wr_en  ),
    .reg_rd_en  ( reg_rd_en  ),
    .pready     ( pready     ),
    .pslverr    ( pslverr    )
  );

  apb_datapath datapath (
    .pclk          ( pclk          ),
    .presetn       ( presetn       ),
    .paddr         ( paddr         ),
    .pwdata        ( pwdata        ),
    .pstrb         ( pstrb         ),
    .reg_wr_en     ( reg_wr_en     ),
    .reg_rd_en     ( reg_rd_en     ),
    .addr_match    ( addr_match    ),
    // Tin hieu TX/RX
    .rx_data       ( rx_data       ),
    .rx_done       ( rx_done       ),
    .parity_error  ( parity_error  ),
    .tx_done       ( tx_done       ),
    .prdata        ( prdata        ),
    .tx_data       ( tx_data       ),
    .start_tx      ( start_tx      ),
    .clear_rx_done ( clear_rx_done ),
    .data_bit_num  ( data_bit_num  ),
    .stop_bit_num  ( stop_bit_num  ),
    .parity_en     ( parity_en     ),
    .parity_type   ( parity_type   )
  );
endmodule