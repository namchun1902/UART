`timescale 1ns/1ps

module tb_top_interface_uart_slave;

  //-------------------------------------------------------------
  // 1. TIN HIEU KET NOI VOI DUT (INTERFACE APB SLAVE)
  //-------------------------------------------------------------
  reg         pclk;
  reg         presetn;
  reg         psel;
  reg         penable;
  reg         pwrite;
  reg  [11:0] paddr;
  reg  [31:0] pwdata;
  reg  [3:0]  pstrb;
  wire [31:0] prdata;
  wire        pready;
  wire        pslverr;

  wire [7:0]  tx_data;
  wire        start_tx;
  reg         tx_done;

  reg  [7:0]  rx_data;
  reg         rx_done;
  reg         parity_error;
  wire        clear_rx_done;

  wire [1:0]  data_bit_num;
  wire        stop_bit_num;
  wire        parity_en;
  wire        parity_type;

  reg [31:0] prdata_sample; // Biến tạm dùng nội bộ trong Testbench

  integer pass_cnt;
  integer err_cnt;

  //-------------------------------------------------------------
  // 2. KHOI TAO DUT
  //-------------------------------------------------------------
  top_interface_uart_slave dut (
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
    .tx_data       ( tx_data       ),
    .start_tx      ( start_tx      ),
    .tx_done       ( tx_done       ),
    .rx_data       ( rx_data       ),
    .rx_done       ( rx_done       ),
    .parity_error  ( parity_error  ),
    .clear_rx_done ( clear_rx_done ),
    .data_bit_num  ( data_bit_num  ),
    .stop_bit_num  ( stop_bit_num  ),
    .parity_en     ( parity_en     ),
    .parity_type   ( parity_type   )
  );

  // Xung clock 50MHz (T = 1/F = 1/50Mhz = 20ns)
  initial begin
    pclk = 0;
    forever #10 pclk = ~pclk;
  end

  //-------------------------------------------------------------
  // 3. 17 EDGE CASES KIEM THU TOAN DIEN CHO KHOI INTERFACE
  //-------------------------------------------------------------
  initial begin
    $dumpfile("tb_top_interface_uart_slave.vcd");
    $dumpvars(0, tb_top_interface_uart_slave);

    pass_cnt     = 0;
    err_cnt      = 0;
    presetn      = 0;
    psel         = 0;
    penable      = 0;
    pwrite       = 0;
    paddr        = 12'h0;
    pwdata       = 32'h0;
    pstrb        = 4'h0;
    tx_done      = 1;
    rx_data      = 8'h0;
    rx_done      = 0;
    parity_error = 0;

    $display("==========================================================");
    $display("BAT DAU KIEM THU 17 EDGE CASES TOAN DIEN KHOI INTERFACE");
    $display("==========================================================");

  // --- TC1: Reset he thong & Gia tri mac dinh ---
    #25; presetn = 1; @(posedge pclk);

    // 1. Trang thai hien tai IDLE
    // MASTER dang o pha SETUP
    @(posedge pclk); #1; // Delay 1ns tranh race condition
    // FSM o IDLE
    psel    = 1'b1;
    penable = 1'b0;
    pwrite  = 0;
    paddr   = 12'h010; // Doc stt_reg

    // 2. Chuyen trang thai sang ACESS
    // MASTER sang pha ACCESS
    @(posedge pclk); #1;
    penable = 1;
    #1;
    // 3. FSM sang ACCESS
    @(posedge pclk) #1;

    // Neu reset thi stt_reg[0] = 1'b1
    if (prdata == 32'h00000001 && pready == 1'b1 && pslverr == 1'b0) begin
      $display("[PASS] TC1: Reset dung, stt_reg = 0x%08h (tx_done = 1)", prdata);
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC1 (Reset): prdata = 0x%08h (mong muon 0x00000001), pready = %b, pslverr = %b", prdata, pready, pslverr);
      err_cnt = err_cnt + 1;
    end
    // Quay ve IDLE
    @(posedge pclk); #1;
    psel    = 0;
    penable = 0;

  // --- TC2: Ghi va Doc tx_data_reg (0x000) ---
    // Ghi 0xA5
    // 1. Pha SETUP cua MASTER
    @(posedge pclk);
      #1; // Tre sau suon clock 1ns
      psel    = 1;
      penable = 0;
      pwrite  = 1;
      paddr   = 12'h000;
      pwdata  = 32'hA5;
      pstrb   = 4'h1;

    @(posedge pclk); // MASTER sang pha ACCESS, Slave sang SETUP
    #1;
    penable = 1;
    @(posedge pclk); // FSM Slave moi sang ACCESS
    @(posedge pclk); #1;
    // Hoan tat ghi -> Keo bus ve IDLE
    psel    = 1'b0;
    penable = 1'b0;
    pwrite  = 1'b0;

    // 2. Lenh doc lai du lieu
    @(posedge pclk); #1;
    // Pha SETUP cua MASTER
    psel    = 1'b1;
    penable = 1'b0;
    pwrite  = 1'b0;
    paddr   = 12'h000;
    @(posedge pclk); #1;
    // MASTER Sang pha ACCESS
    penable = 1'b1;

    // Slave sang ACCESS
    @(posedge pclk); #1;
    // Doi tin hieu on dinh

    if (tx_data == 8'ha5 && prdata[7:0] == 8'ha5) begin
      $display("[PASS] TC2: Ghi doc tx_data_reg thanh cong (0xA5)");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC2 (Ghi/Doc tx_data_reg): tx_data = 0x%02h, prdata = 0x%08h (mong muon 0xa5)", tx_data, prdata);
      err_cnt = err_cnt + 1;
    end
    // Reset ve IDLE
    @(posedge pclk); #1;
    psel    = 0;
    penable = 0;
    @(posedge pclk);

    // --- TC3: Cau hinh cfg_reg (0x008) ---
    // Pha SETUP cua FSM - Slave o IDLE
    @(posedge pclk); #1;
    psel    = 1;
    penable = 0;
    pwrite  = 1;
    paddr   = 12'h008;
    pwdata  = 32'h0000001F;
    pstrb   = 4'h1;
    // Pha ACCESS MASTER - SETUP cua Slave
    @(posedge pclk); #1;
    penable = 1;
    // Slave sang ACCESS
    @(posedge pclk); #1;
    // Ve IDLE
    @(posedge pclk); #1;
    psel    = 0;
    penable = 0;

    @(posedge pclk); #1;
    // Doc lai 0x008
    // Pha SETUP MASTER - IDLE o Slave
    @(posedge pclk); #1;
    psel    = 1;
    penable = 0;
    pwrite  = 0;
    paddr   = 12'h008;
    // MASTER sang pha ACCESS
    @(posedge pclk); #1;
    penable = 1;
    @(posedge pclk); #1; // Slave sang pha ACCESS
    if (data_bit_num == 2'b11 && stop_bit_num == 1'b1 && parity_en == 1'b1 && parity_type == 1'b1 && prdata[4:0] == 5'b11111) begin
      $display("[PASS] TC3: Cau hinh cfg_reg thanh cong (8b, 2 stop, Even)");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC3 (Cau hinh cfg_reg): prdata = 0x%08h (mong muon 0x1F), cfg = {data=%b, stop=%b, p_en=%b, p_type=%b}", prdata, data_bit_num, stop_bit_num, parity_en, parity_type);
      err_cnt = err_cnt + 1;
    end
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    // --- TC4: Auto-Clear start_tx trong ctrl_reg (0x00C) ---
    // 1. MASTER o pha SETUP
    @(posedge pclk); #1;
    psel    = 1;
    penable = 0;
    pwrite  = 1;
    paddr   = 12'h00C;
    pwdata  = 32'h01;
    pstrb   = 4'h1;

    // 2. Chuyen pha
    @(posedge pclk); #1; // MASTER sang pha ACCESS
    penable = 1;

    // 3. FSM Slave sang ACCESS
    @(posedge pclk); #1; // Slave sang ACCESS

    //4. Suon clock cho pwdata vao ctrl_reg, start_tx bat len 1
    // FSM sang IDLE
    @(posedge pclk); #1;
    psel    = 1'b0;
    penable = 1'b0;
    pwrite  = 1'b0;
    #1;

    // Check start_tx len 1 hay chua
    if (start_tx == 1'b1) begin
      $display("[PASS] TC4.1: start_tx da bat len 1 thanh cong");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC4.1 (start_tx bat len 1): start_tx = %b (mong muon 1)", start_tx);
      err_cnt = err_cnt + 1;
    end

    // pwrite = 0 --> reg_wr_en = 0 --> wr_ctrl_en = 0 --> start_tx = ctrl_reg[0] <= 1'b0
    @(posedge pclk); #1; // Chu ky tiep theo khong con lenh ghi, start_tx tu dong xoa ve 0!
    if (start_tx == 1'b0) begin
      $display("[PASS] TC4.2: start_tx da tu dong xoa ve 0 sau 1 clock (Auto-Clear)");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC4.2 (start_tx tu xoa ve 0): start_tx = %b (mong muon 0)", start_tx);
      err_cnt = err_cnt + 1;
    end
    @(posedge pclk);

  // --- TC5: RX nhan du lieu va clear_rx_done khi doc 0x004 ---
    // Trang thai IDLE
    @(posedge pclk); #1;
    // Tin hieu tu UART_RX sang
    rx_data      = 8'h3C; // Du lieu vao prdata[7:0]
    rx_done      = 1;
    parity_error = 1;

    // Pha SETUP cua MASTER
    @(posedge pclk); #1;
    psel    = 1;
    penable = 0;
    pwrite  = 0;
    paddr   = 12'h004;
    // Pha ACCESS cua MASTER - Slave o SETUP
    @(posedge pclk); #1;
    penable = 1;
    // Slave sang ACCESS
    @(posedge pclk); #1;

    // FSM: reg_rd_en = !pwrite && addr_match && penable
    // clear_rx_done = (paddr == 12'h004) && reg_rd_en
    if (clear_rx_done == 1'b1 && prdata[7:0] == 8'h3C) begin
      $display("[PASS] TC5: Doc rx_data_reg dung (0x3C) va phat xung clear_rx_done = 1");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC5 (RX nhan va clear_rx_done): prdata = 0x%08h (mong muon 0x3C), clear_rx_done = %b (mong muon 1)", prdata, clear_rx_done);
      err_cnt = err_cnt + 1;
    end

    // Reset ve IDLE
    @(posedge pclk); #1;
    psel         = 0;
    penable      = 0;
    rx_done      = 0;
    parity_error = 0;
    @(posedge pclk); #1;

    // --- TC6: Read-After-Write (Ghi xong doc lai ngay lap tuc) ---
    // 1. Pha SETUP cua MASTER
    // Ghi 0xB4
    @(posedge pclk); #1;
    // Tin hieu Bus APB
    psel    = 1;
    penable = 0;
    pwrite  = 1;
    paddr   = 12'h000;
    pwdata  = 32'hB4;
    pstrb   = 4'h1;
    
    // 2. MASTER sang pha ACCESS - Slave sang SETUP
    @(posedge pclk); #1;
    penable = 1;

    // 3. Slave sang ACCESS
    @(posedge pclk); #1;
    // reg_wr_en = pwrite && addr_match && penable = 1
    // wr_tx_data_en = reg_wr_en && pstrb[0] && (paddr == 12'h000) = 1
    // tx_data_reg <= pwdata = 32'hB4
    // prdata = tx_data_reg

    @(posedge pclk); #1; // Doi Slave ve IDLE
    // RESET tin hieu ve 0
    psel    = 0;
    penable = 0;

    // Tiep tuc pha SETUP cua MASTER
    @(posedge pclk); #1;
    // 0xB4 da duoc chot vao tx_data_reg!
    // Doc ngay 0x000
    psel    = 1;
    penable = 0;
    pwrite  = 0;
    paddr   = 12'h000;
    // MASTER sang ACCESS
    @(posedge pclk); #1;
    penable = 1;
    // Slave sang ACCESS
    @(posedge pclk); #1;

    if (prdata[7:0] == 8'hB4 && tx_data == 8'hB4) begin
      $display("[PASS] TC6: Read-After-Write thanh cong, lay dung 0xB4 ngay lap tuc");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC6 (Read-After-Write): prdata = 0x%08h, tx_data = 0x%02h (mong muon 0xB4)", prdata, tx_data);
      err_cnt = err_cnt + 1;
    end
    // Ve IDLE
    @(posedge pclk); #1;
    psel    = 0;
    penable = 0;
    @(posedge pclk);


  // --- TC7: Back-to-Back transfers (2 lenh ghi lien tiep khong IDLE) ---
    // 1. Ghi 1
    // (Ghi 0x11 vào 0x000)
    // Pha SETUP cua MASTER
    @(posedge pclk); #1; // CLK 1
    psel    = 1'b1;
    penable = 1'b0;
    pwrite  = 1'b1;
    paddr   = 12'h000;
    pwdata  = 32'h11;
    pstrb   = 4'h1;
    
    // MASTER sang pha ACCESS 1 - FSM Slave sang SETUP 1
    @(posedge pclk); #1; // CLK 2
    penable = 1'b1;

    // FSM Slave sang pha ACCESS 1
    // Giu nguyen penable = 1 va pwdata = 0x11 cho den het chu ky nay
    @(posedge pclk);     // CLK 3

    // 2. Chuyen sang lenh ghi thu 2 luon (SETUP 2 MASTER)
    @(posedge pclk); #1; // CLK 4: Suon clock nay chot 0x11 vao thanh ghi 0x000

    // Ngay sau suon clock 1ns, MASTER phat pha SETUP 2
    psel    = 1'b1;         // Giu psel = 1 khong cho Slave ve IDLE
    penable = 1'b0;      // Ha penable = 0
    pwrite  = 1'b1;       // Van la lenh ghi

    paddr  = 12'h000; 
    pwdata = 32'h22;     // Dua du lieu 0x22 moi len Bus APB
    pstrb  = 4'h1;
    
    // 3. Lenh ghi 2
    // MASTER phat pha ACCESS 2 - Slave sang thang SETUP 2 luon
    @(posedge pclk); #1; // CLK 5
    penable = 1; // ACCESS Ghi 2

    // FSM Slave sang ACCESS 2 - Giu penable = 1 va pwdata = 0x22 cho den het chu ky nay
    @(posedge pclk); #1; // CLK 6 
    // Ket thuc Ghi 2

    // 4. Ket thuc ca 2 lenh ghi
    // Slave ve IDLE
    @(posedge pclk); #1; // CLK 7: suon clock nay chot 0x22 vao thanh ghi
    // MASTER reset tin hieu, Bus ve IDLE 
    psel    = 1'b0;
    penable = 1'b0;
    pwrite  = 1'b0;
    #1;

    // tx_data_reg <= pwdata = 32'h22
    if (tx_data == 8'h22) begin
      $display("[PASS] TC7: Back-to-Back thanh cong, tx_data = 0x22");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC7 (Back-to-Back): tx_data = 0x%02h (mong muon 0x22)", tx_data);
      err_cnt = err_cnt + 1;
    end
    @(posedge pclk);


  // --- TC8: Dia chi khong hop le (pslverr) ---
    // 1. MASTER phat ra pha SETUP
    @(posedge pclk); #1;
    psel    = 1;
    penable = 0;
    pwrite  = 1;
    paddr   = 12'h100;      // Dia chi khong ton tai
    pwdata  = 32'h1234;
    pstrb   = 4'h1;

    // 2. MASTER phat ra pha ACCESS - FSM Slave chuyen sang SETUP
    @(posedge pclk); #1;
    penable = 1;
    
    // 3. FSM Slave sang ACCESS
    @(posedge pclk); #1;    // addr_match = 0 --> pslverr = 1

    if (pslverr == 1'b1 && pready == 1'b1) begin
      $display("[PASS] TC8: Bao loi pslverr = 1 khi truy cap dia chi sai 0x100");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC8 (Dia chi sai 0x100): pslverr = %b (mong muon 1), pready = %b (mong muon 1)", pslverr, pready);
      err_cnt = err_cnt + 1;
    end
    @(posedge pclk); #1;
    psel = 0;
    penable = 0;
    @(posedge pclk);

  // --- TC9: Bao ve thanh ghi Read-Only (rx_data_reg 0x004) ---
    // prdata = 32'h3C tu TC5
    // Co tinh ghi de rac 0xFF vao rx_data_reg
    // 1. MASTER phat ra pha SETUP
    @(posedge pclk); #1;
    psel    = 1;
    penable = 0;
    pwrite  = 1;          // Tin hieu ghi
    paddr   = 12'h004;    // rx_data_reg - thanh ghi Read Only
    pwdata  = 32'hFF;     // Gia tri rac
    pstrb   = 4'h1;

    // 2. MASTER phat ra pha ACCESS - FSM Slave chuyen sang SETUP
    @(posedge pclk); #1;
    penable = 1;

    // 3. FSM Slave chuyen sang ACCESS
    @(posedge pclk); #1;
    // Write Decoder khong hoat dong do paddr = 0x04
    psel    = 0;
    penable = 0;

    // 4. FSM Slave quay ve IDLE
    @(posedge pclk);
    // Doc lai 0x004
    // 5. Pha SETUP 2 cua MASTER - doc lai rx_data_reg
    @(posedge pclk); #1;
    psel    = 1;
    penable = 0;
    pwrite  = 0;          // Lenh doc
    paddr   = 12'h004;    // Doc thanh ghi rx_data_reg
    // 6. Pha ACCESS 2 cua MASTER
    @(posedge pclk); #1;
    penable = 1;
    // 7. Slave chuyen sang ACCESS 2 - Doc du lieu
    @(posedge pclk); #1;
    if (prdata[7:0] == 8'h3C) begin
      $display("[PASS] TC9: Thanh ghi RO (0x004) duoc bao ve, khong bi ghi de rac");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC9 (Bao ve Read-Only 0x004): prdata = 0x%08h (mong muon 0x3C khong bi ghi de)", prdata);
      err_cnt = err_cnt + 1;
    end
    @(posedge pclk); #1;
    psel    = 0;
    penable = 0;
    @(posedge pclk);

  // --- TC 10: Byte Strobe pstrb[0] = 0 chan ghi ---
    // 1. MASTER phat ra pha SETUP
    @(posedge pclk); #1;
    psel = 1;
    penable = 0;
    pwrite = 1;       // Tin hieu ghi
    paddr = 12'h000;  // tx_data_reg
    pwdata = 32'h99;
    pstrb = 4'h0;     // Khong chon ghi vao cum byte nao ca

    // 2. MASTER phat pha ACCESS
    @(posedge pclk); #1;
    penable = 1;
    // 3. Slave chuyen sang ACCESS
    @(posedge pclk); #1;
    // RESET tin hieu
    psel = 0;
    penable = 0;
    @(posedge pclk); #1;

    // tx_data_reg = 0x22 o TC7 giu nguyen
    if (tx_data == 8'h22) begin
      $display("[PASS] TC10: pstrb[0] = 0 chan ghi dung, du lieu giu nguyen 0x22");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC10 (Byte Strobe pstrb=0): tx_data = 0x%02h (mong muon 0x22 khong bi ghi de)", tx_data);
      err_cnt = err_cnt + 1;
    end
    @(posedge pclk);#1;

  // --- TC11: Race Condition (RX nhan byte moi 0x7E dung luc CPU dang doc 0x004) ---
    // 1. MASTER phat ra pha SETUP (Lan doc 1)
    @(posedge pclk); #1;
    psel    = 1;
    penable = 0;
    pwrite  = 0;        // Doc --> reg_rd_en = 1
    paddr   = 12'h004;  // rx_data_reg

    // 2. MASTER phat ra pha ACCESS
    // rx_data_reg cux dang duoc noi voi MUX doi reg_rd_en tu FSM de cho ra prdata
    @(posedge pclk); #1;
    penable = 1;
    // Du lieu duoc RX gui sang cung luc - Doi truoc rx_data_reg cho xung clock
    rx_data = 8'h7E; // Du lieu rx_data moi duoc UART_RX gui sang
    rx_done = 1;     // RX gui byte moi

    // 3. Chot prdata ngay tai suon clock ket thuc ACCESS 
    // prdata_sample nhan du lieu cu cua rx_data_reg truyen thang ve Bus APB MASTER
    // Dong thoi rx_data = 0x7E, rx_done = 1 moi duoc luu vao rx_data_reg
    @(posedge pclk);
    prdata_sample = prdata;
    #1; // Luc nay prdata da bang 0x7E
    psel    = 0;
    penable = 0;
    rx_done = 0;

    // TESTPOINT 1: Kiem tra lan doc 1 -> Phai doc an toan gia tri cu (0x3C) - Gia tri gui ve Bus APB
    if (prdata_sample[7:0] == 8'h3C) begin
      $display("[PASS] TC11.1: Lan doc 1 tra ve an toan gia tri CU (0x3C)");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC11.1 (Lan doc 1): prdata_sample = 0x%02h (mong muon 0x3C)", prdata_sample[7:0]);
      err_cnt = err_cnt + 1;
    end
    #1;

    // Doi 1 suon clock de ve IDLE
    @(posedge pclk); #1;

    // 4. MASTER phat ra pha SETUP 2
    // Doc lai 0x004
    @(posedge pclk); #1;
    psel    = 1;
    penable = 0;
    pwrite  = 0;
    paddr   = 12'h004;

    // 5. MASTER phat ra pha ACCESS 2 - Slave chuyen sang SETUP
    @(posedge pclk); #1;
    penable = 1;
    // 6. Slave chuyen sang ACCESS
    @(posedge pclk); #1;

    if (prdata[7:0] == 8'h7E) begin
      $display("[PASS] TC11.2: Byte moi 0x7E duoc chot an toan sau Race Condition!");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC11.2 (Race Condition RX): prdata = 0x%08h (mong muon 0x7E)", prdata);
      err_cnt = err_cnt + 1;
    end

    // RESET VE IDLE
    @(posedge pclk); #1;
    psel    = 0;
    penable = 0;
    @(posedge pclk); #1;

  // --- TC12: Chong kich hoat nham clear_rx_done (False-Trigger Isolation) ---
    rx_done = 1;
    // Doc 0x000 (tx_data_reg)
    // 1. Pha SETUP cua MASTER
    @(posedge pclk); #1;
    psel    = 1;
    penable = 0;
    pwrite  = 0;        // Keo reg_rd_en len 1
    paddr   = 12'h000;  // tx_data_reg

    // 2. Pha ACCESS cua MASTER
    @(posedge pclk); #1;
    penable = 1;

    // 3. Slave chuyen sang ACCESS
    @(posedge pclk); #1;

    // clear_rx_done = (paddr == 12'h004) && reg_rd_en = 0
    if (clear_rx_done == 1'b0) begin
      $display("[PASS] TC12.1: Doc 0x000 khong gay xung gia clear_rx_done");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC12.1 (Doc 0x000): clear_rx_done = %b (mong muon 0)", clear_rx_done);
      err_cnt = err_cnt + 1;
    end

  // TC12.2
    // Reset ve IDLE
    @(posedge pclk); #1;
    psel = 0;
    penable = 0;

    // Ghi vao 0x004 (chi doc moi duoc phep phat xung clear)
    // 1. MASTER phat ra pha SETUP
    @(posedge pclk); #1;
    psel    = 1;
    penable = 0;
    pwrite  = 1;        // Tin hieu ghi
    paddr   = 12'h004;  // rx_data_reg
    pwdata  = 32'h0;
    pstrb   = 4'h1;     // Chi bat len luc can Ghi
    // 2. MASTER phat ra pha ACCESS
    @(posedge pclk); #1;
    penable = 1;
    // 3. Slave chuyen sang ACCESS
    @(posedge pclk); #1;

    // pwrite  = 1;
    // reg_rd_en = !pwrite && addr_match && penable
    // clear_rx_done = (paddr == 12'h004) && reg_rd_en = 0
    if (clear_rx_done == 1'b0) begin
      $display("[PASS] TC12.2: Ghi 0x004 khong gay xung gia clear_rx_done");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC12.2 (Ghi 0x004): clear_rx_done = %b (mong muon 0)", clear_rx_done);
      err_cnt = err_cnt + 1;
    end
    @(posedge pclk); #1;
    psel = 0;
    penable = 0;
    rx_done = 0;
    @(posedge pclk); #1;

  // --- TC13: Kiem tra toan bo bit stt_reg (0x010) & Bao ve Read-Only ---
    // TC13.1
    // Cho parity_error = 1, rx_done = 1, tx_done = 0
    // -> stt_reg = 3'b110 = 0x06
    parity_error = 1;
    rx_done      = 1;
    tx_done      = 0;

    // 1. MASTER phat ra pha SETUP
    @(posedge pclk); #1;
    psel = 1;
    penable = 0;
    pwrite = 0;       // Tin hieu doc
    paddr = 12'h010;  // stt_reg

    // 2. MASTER phat ra pha ACCESS
    @(posedge pclk); #1;
    penable = 1;
    // 3. Slave chuyen sang ACCESS
    @(posedge pclk); #1;

    // stt_reg[2:0] = 3'b110
    if (prdata[2:0] == 3'b110) begin
      $display("[PASS] TC13.1: Doc stt_reg dung bit {parity_err=1, rx_done=1, tx_done=0} = 0x%01h", prdata[2:0]);
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC13.1 (Doc stt_reg): prdata = 0x%08h (mong muon [2:0]=3'b110)", prdata);
      err_cnt = err_cnt + 1;
    end

  // TC 14.2
    // RESET ve IDLE
    @(posedge pclk); #1;
    psel = 0;
    penable = 0;

    // Co tinh ghi de 32'hFFFFFFFF vao 0x010 de kiem tra bao ve Read-Only
    // 1. MASTER phat ra pha SETUP
    @(posedge pclk); #1;
    psel    = 1;
    penable = 0;
    pwrite  = 1;            // Tin hieu ghi
    paddr   = 12'h010;      // stt_reg
    pwdata  = 32'hFFFFFFFF;
    pstrb   = 4'b1111;

    // 2. MASTER phat ra pha ACCESS
    @(posedge pclk); #1;
    penable = 1;

    // 3. Slave chuyen sang ACCESS
    @(posedge pclk); #1;
    psel = 0;
    penable = 0;
    // Doc lai 0x010 kiem tra gia tri khong bi anh huong

    // 1. MASTER phat ra pha SETUP
    @(posedge pclk); #1;
    psel = 1;
    penable = 0;
    pwrite = 0;
    paddr = 12'h010;
    // 2. MASTER phat ra pha ACCESS
    @(posedge pclk); #1;
    penable = 1;
    // 3. Slave sang ACCESS
    @(posedge pclk); #1;

    // prdata giu nguyen gia tri 3'b110
    if (prdata[2:0] == 3'b110) begin
      $display("[PASS] TC13.2: stt_reg (0x010) la Read-Only, khong the bi ghi de boi CPU");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC13.2 (Ghi de stt_reg): prdata = 0x%08h (bi ghi de)", prdata);
      err_cnt = err_cnt + 1;
    end
    @(posedge pclk); #1;
    // Reset cac tin hieu cua RX sang, chuyen Slave ve IDLE
    psel         = 0;
    penable      = 0;
    parity_error = 0;
    rx_done      = 0;
    tx_done      = 1;
    @(posedge pclk);

  // --- TC14: Dia chi bien ke can (0x014) va unaligned (0x002) phat pslverr ---
    // Truy cap 0x014 (ngay sau thanh ghi cuoi cung 0x010)
    // 1. MASTER phat ra pha SETUP
    @(posedge pclk); #1;
    psel = 1;
    penable = 0;
    pwrite = 0;
    paddr = 12'h014;
    // 2. MASTER phat ra pha ACCESS
    @(posedge pclk); #1;
    penable = 1;
    // 3. Slave sang ACCESS
    @(posedge pclk); #1;

    // Khong co dia chi thanh ghi paddr = 0x014
    if (pslverr == 1'b1 && pready == 1'b1) begin
      $display("[PASS] TC14.1: pslverr = 1 khi doc dia chi bien khong hop le 0x014");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC14.1 (Dia chi 0x014): pslverr = %b, pready = %b (mong muon deu 1)", pslverr, pready);
      err_cnt = err_cnt + 1;
    end

  // TC 15.2
    // Truy cap 0x002 (nam xen giua 0x000 va 0x004)
    // Co tinh ghi vao thanh ghi 0x002 khong ton tai
    // RESET ve IDLE
    @(posedge pclk); #1;
    psel = 0;
    penable = 0;
    // Truy cap 0x002 (dia chi le giua 0x000 va 0x004)
    // 1. MASTER phat ra pha SETUP
    @(posedge pclk); #1;
    psel = 1;
    penable = 0;
    pwrite = 1;       // Ghi
    paddr = 12'h002;  // Dia chi khong ton tai
    pwdata = 32'hAA;
    pstrb = 4'h1;
    // 2. MASTER phat ra pha ACCESS
    @(posedge pclk); #1;
    penable = 1;
    // 3. Slave sang ACCESS
    @(posedge pclk); #1;

    // addr_match = 0 --> pslverr = 1
    if (pslverr == 1'b1 && pready == 1'b1) begin
      $display("[PASS] TC14.2: pslverr = 1 khi truy cap dia chi khong can le 0x002");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC14.2 (Dia chi 0x002): pslverr = %b, pready = %b (mong muon deu 1)", pslverr, pready);
      err_cnt = err_cnt + 1;
    end
    @(posedge pclk); #1;
    psel = 0;
    penable = 0;
    @(posedge pclk);

  // --- TC15: Bus o IDLE (psel = 0) ---
    // Cho penable = 1, pwrite = 1, pwdata = 32'hFF vao 0x000 nhung psel = 0
    // 1. MASTER phat ra pha SETUP
    @(posedge pclk); #1;
    psel = 0;
    penable = 0;
    pwrite = 1;
    paddr = 12'h000;
    pwdata = 32'hFF;
    pstrb = 4'h1;
    // 2. MASTER phat ra pha ACCESS
    @(posedge pclk); #1;
    penable = 1'b1;
    // 3. Slave sang ACCESS
    @(posedge pclk); #1;

    // tx_data phai giu nguyen gia tri 8'h22
    if (pready == 1'b0 && tx_data != 8'hFF && tx_data == 8'h22) begin
      $display("[PASS] TC15: Bus o IDLE (psel=0) mien nhiem voi tin hieu la tren bus");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC15 (Bus Noise psel=0): pready = %b, tx_data = 0x%02h", pready, tx_data);
      err_cnt = err_cnt + 1;
    end
    @(posedge pclk); #1;
    penable = 0;
    pwrite = 0;
    @(posedge pclk);

  // --- TC16: Reset bat dong bo giua chu ky giao tiep APB ---
    // 1. MASTER phat ra pha SETUP
    @(posedge pclk); #1;
    psel = 1;
    penable = 0;
    pwrite = 1;       // Ghi
    paddr = 12'h000;  // tx_data_reg
    pwdata = 32'h5A;
    pstrb = 4'h1;

    // 2. MASTER phat ra pha ACCESS
    @(posedge pclk); #1;
    penable = 1'b1; // ACCESS phase

    // 3. Kich hoat reset bat dong bo ngay giua pha ACCESS (lech 3ns)
    #3;
    presetn = 1'b0;              // Reset bat dong bo ngay lap tuc
    #10;

    // FSM ve IDLE, tx_data khong bi ghi nham khi reset
    if (pready == 1'b0 && dut.fsm.current_state == 2'b00 && tx_data == 8'h00) begin
      $display("[PASS] TC16: Reset bat dong bo thanh cong, FSM lap tuc tro ve IDLE va huy lenh ghi (tx_data reset ve 0x00)");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] TC16 (Mid-transfer Reset): pready = %b, state = %b (mong muon pready=0, IDLE=00)", pready, dut.fsm.current_state);
      err_cnt = err_cnt + 1;
    end
    #15;
    presetn = 1;
    psel = 0;
    penable = 0;
    pwrite = 0;
    @(posedge pclk);

    // --- TONG KET ---
    $display("\n==========================================================");
    $display("TONG KET KIEM THU INTERFACE APB SLAVE:");
    $display("SO TESTCASE THANH CONG: %0d", pass_cnt);
    $display("SO TESTCASE THAT BAI:   %0d", err_cnt);
    if (err_cnt == 0) $display("KET LUAN: >>> INTERFACE APB SLAVE DAT DIEM TOI DA! <<<");
    else              $display("KET LUAN: >>> CO LOI CAN KIEM TRA! <<<");
    $display("==========================================================");

    #50;
    $finish;
  end

endmodule

