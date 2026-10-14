`timescale 1ns/1ps

module tb_apb_uart_edge_cases;

  //-------------------------------------------------------------
  // 1. KHAI BAO TIN HIEU KET NOI VOI APB UART
  //-------------------------------------------------------------
  reg         clk;
  reg         reset_n;
  reg         pclk;
  reg         presetn;

  reg         psel;
  reg         penable;
  reg         pwrite;
  reg  [3:0]  pstrb;
  reg  [11:0] paddr;
  reg  [31:0] pwdata;
  wire        pready;
  wire        pslverr;
  wire [31:0] prdata;

  wire        tx;
  wire        rts_n;
  reg         cts_n;

  // Bo dieu khien chan RX: Ho tro ca Loopback va Inject ngoai vi
  reg         rx_override;   // 0: Loopback (rx = tx), 1: Inject thu cong
  reg         rx_drv;        // Gia tri inject thu cong vao chan rx
  wire        rx = rx_override ? rx_drv : tx;

  integer pass_cnt;
  integer err_cnt;
  integer t_start, t_end, t_delta;

  //-------------------------------------------------------------
  // 2. KHOI TAO DUT (FCLK = 50MHz, BAUDRATE = 1MHz -> 50 clock/bit)
  //-------------------------------------------------------------
  apb_uart #(
    .FCLK     (50000000),
    .BAUDRATE (1000000)
  ) dut (
    .clk      (clk),
    .reset_n  (reset_n),
    .pclk     (pclk),
    .presetn  (presetn),
    .psel     (psel),
    .penable  (penable),
    .pwrite   (pwrite),
    .pstrb    (pstrb),
    .paddr    (paddr),
    .pwdata   (pwdata),
    .pready   (pready),
    .pslverr  (pslverr),
    .prdata   (prdata),
    .rx       (rx),
    .cts_n    (cts_n),
    .tx       (tx),
    .rts_n    (rts_n)
  );

  // Tao xung clock 50MHz (T = 20ns, #10)
  initial begin
    clk = 0;
    pclk = 0;
    forever begin
      #10 clk = ~clk; pclk = ~pclk;
    end
  end

  //-------------------------------------------------------------
  // 3. TASK HO TRO GUI SERIAL VAO CHAN RX (CHO INJECT LOI)
  // 1 bit = 50 chu ky clock (1us) tai 1Mbps / 50MHz
  //-------------------------------------------------------------
  task send_serial_byte;
    input [7:0] data;
    input [1:0] bit_num;     // 00: 5b, 01: 6b, 10: 7b, 11: 8b
    input       has_parity;
    input       parity_val;  // Gia tri bit parity muon truyen (dung hoac sai)
    input       two_stop;
    integer i, n_bits;
    begin
      case(bit_num)
        2'b00: n_bits = 5;
        2'b01: n_bits = 6;
        2'b10: n_bits = 7;
        default: n_bits = 8;
      endcase

      rx_override = 1;
      // 1. Start bit = 0
      rx_drv = 1'b0;
      repeat (50) @(posedge clk);

      // 2. Data bits (LSB first)
      for (i = 0; i < n_bits; i = i + 1) begin
        rx_drv = data[i];
        repeat (50) @(posedge clk);
      end

      // 3. Parity bit (neu co)
      if (has_parity) begin
        rx_drv = parity_val;
        repeat (50) @(posedge clk);
      end

      // 4. Stop bit(s) = 1
      rx_drv = 1'b1;
      repeat (50) @(posedge clk);
      if (two_stop) begin
        repeat (50) @(posedge clk);
      end

      rx_override = 0; // Tra lai quyen Loopback
    end
  endtask

  //-------------------------------------------------------------
  // 4. 6 EDGE CASES CHUYEN SAU CHO TOAN HE THONG UART
  //-------------------------------------------------------------
  initial begin
    $dumpfile("tb_apb_uart_edge_cases.vcd");
    $dumpvars(0, tb_apb_uart_edge_cases);

    pass_cnt    = 0;
    err_cnt     = 0;
    reset_n     = 0;
    presetn     = 0;
    psel        = 0;
    penable     = 0;
    pwrite      = 0;
    pstrb       = 4'h0;
    paddr       = 12'h0;
    pwdata      = 32'h0;
    cts_n       = 0;
    rx_override = 0;
    rx_drv      = 1'b1;

    $display("==========================================================");
    $display("BAT DAU KIEM THU 6 EDGE CASES CHUYEN SAU TOAN HE THONG UART");
    $display("MUC TIEU: KIEM TRA LOI & HANH VI PHAN CUNG TRUNG THUC");
    $display("==========================================================");

    // Reset ban dau
    #40; reset_n = 1; presetn = 1; @(posedge pclk);

    // ==========================================================
    // CASE 1: BOM LOI PARITY (PARITY ERROR INJECTION)
    // Cau hinh: 8 data bits, 1 stop bit, Even Parity (cfg_reg = 0x1B)
    // Du lieu: 8'h3C (0011_1100, 4 bit 1 -> Even parity dung la 0)
    // INJECT: Co tinh gui Parity = 1 (sai parity)
    // Mong muon: Bit 2 cua stt_reg (parity_error) phai bat len 1!
    // ==========================================================
    $display("\n--- CASE 1: BOM LOI PARITY (PARITY ERROR INJECTION) ---");
    // Ghi cfg_reg = 0x1B (8b, 1 stop, Parity Even)
    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h008; pwdata = 32'h1B; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk); #1;

    // Inject byte 0x3C voi Parity bit = 1 (SAI PARITY!)
    send_serial_byte(8'h3C, 2'b11, 1'b1, 1'b1, 1'b0);
    repeat (100) @(posedge pclk);

    // Doc stt_reg (0x010) kiem tra co parity_error (bit 2)
    @(posedge pclk); psel = 1; penable = 0; pwrite = 0; paddr = 12'h010;
    @(posedge pclk); penable = 1;
    @(posedge pclk); #1;
    if (prdata[2] == 1'b1) begin
      $display("[PASS] CASE 1: He thong phat hien loi Parity thanh cong! stt_reg = 0x%08h (bit 2 = 1)", prdata);
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] CASE 1: LOI HE THONG! Gui sai Parity nhung co parity_error KHONG bat! stt_reg = 0x%08h (bit 2 = 0)", prdata);
      err_cnt = err_cnt + 1;
    end
    psel = 0; penable = 0; @(posedge pclk);

    // Xoa co bang cach doc rx_data_reg (0x004)
    @(posedge pclk); psel = 1; penable = 0; pwrite = 0; paddr = 12'h004;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk); #1;


    // ==========================================================
    // CASE 2: LOC NHIEU GAI XUNG START GIA (FALSE START GLITCH FILTER)
    // Tinh huong: rx bi nhieu sut xuong 0 trong 5 clock (100ns << 1000ns)
    // Mong muon: RX phai bo qua xung nhieu nay, rx_done khong duoc bat len 1.
    // Sau do gui 1 byte that 0x99, RX van phai nhan binh thuong (khong bi treo FSM).
    // ==========================================================
    $display("\n--- CASE 2: LOC NHIEU XUNG START GIA (FALSE START FILTER) ---");
    rx_override = 1; rx_drv = 1'b1;
    repeat (20) @(posedge clk);

    // Gay nhieu gai: keo rx xuong 0 trong 5 clock
    rx_drv = 1'b0;
    repeat (5) @(posedge clk);
    rx_drv = 1'b1; // Tro ve IDLE
    rx_override = 0;

    // Cho 600 clock xem RX co bi kich hoat nham khong
    repeat (600) @(posedge pclk);

    // Doc stt_reg kiem tra co rx_done (bit 1)
    @(posedge pclk); psel = 1; penable = 0; pwrite = 0; paddr = 12'h010;
    @(posedge pclk); penable = 1;
    @(posedge pclk); #1;
    if (prdata[1] == 1'b0) begin
      $display("[PASS] CASE 2.1: Bo qua xung gai thanh cong! rx_done khong bi kich hoat nham.");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] CASE 2.1: LOI PHAN CUNG! Xung gai 100ns bi coi la Start bit that! rx_done = 1");
      err_cnt = err_cnt + 1;
    end
    psel = 0; penable = 0; @(posedge pclk);

    // Kiem tra tiep: Sau nhieu gai, truyen byte that 0x99 (8b, no parity)
    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h008; pwdata = 32'h03; pstrb = 4'h1; // No parity
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h000; pwdata = 32'h99; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h00C; pwdata = 32'h01; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    repeat (600) @(posedge pclk);

    // Doc ket qua byte 0x99
    @(posedge pclk); psel = 1; penable = 0; pwrite = 0; paddr = 12'h004;
    @(posedge pclk); penable = 1;
    @(posedge pclk); #1;
    if (prdata[7:0] == 8'h99) begin
      $display("[PASS] CASE 2.2: RX hoat dong binh thuong sau khi gap xung nhieu gai (Nhan dung 0x99)");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] CASE 2.2: LOI! RX bi treo FSM sau xung nhieu gai! prdata = 0x%02h (mong muon 0x99)", prdata[7:0]);
      err_cnt = err_cnt + 1;
    end
    psel = 0; penable = 0; @(posedge pclk);


    // ==========================================================
    // CASE 3: CHE DO 5-BIT DATA (data_bit_num = 2'b00)
    // Cau hinh: 5 data bits, 1 stop bit, no parity (cfg_reg = 0x00)
    // CPU ghi vao tx_data_reg gia tri 8'hFF (toan bit 1).
    // Mong muon: TX chi duoc phat 5 bit va RX nhan dung 5'b11111 = 8'h1F.
    // 3 bit cao [7:5] phai bang 0!
    // ==========================================================
    $display("\n--- CASE 3: CHE DO 5-BIT DATA (KIEM TRA BIT MAT NA) ---");
    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h008; pwdata = 32'h00; pstrb = 4'h1; // 5b, 1 stop, no parity
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h000; pwdata = 32'hFF; pstrb = 4'h1; // Ghi 0xFF
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h00C; pwdata = 32'h01; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    repeat (500) @(posedge pclk);

    @(posedge pclk); psel = 1; penable = 0; pwrite = 0; paddr = 12'h004;
    @(posedge pclk); penable = 1;
    @(posedge pclk); #1;
    if (prdata[7:0] == 8'h1F) begin
      $display("[PASS] CASE 3: Che do 5-bit dung chuan! Nhan dung 0x1F (3 bit cao [7:5] duoc xoa sach)");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] CASE 3: LOI CHE DO 5-BIT! prdata = 0x%02h (mong muon 0x1F, bi lem bit cao)", prdata[7:0]);
      err_cnt = err_cnt + 1;
    end
    psel = 0; penable = 0; @(posedge pclk);


    // ==========================================================
    // CASE 4: CHE DO 2 STOP BITS (stop_bit_num = 1)
    // Cau hinh: 8 data bits, 2 stop bits, no parity (cfg_reg = 0x07)
    // Mong muon: Khung truyen co 11 bit (1 start + 8 data + 2 stop).
    // TX phai phat dung 2 stop bits va RX phai xac thuc du 2 stop bits.
    // ==========================================================
    $display("\n--- CASE 4: CHE DO 2 STOP BITS (8 DATA + 2 STOP BITS) ---");
    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h008; pwdata = 32'h07; pstrb = 4'h1; // 8b, 2 stop, no parity
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h000; pwdata = 32'h5A; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h00C; pwdata = 32'h01; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    // Cho 650 clock (11 bit x 50 = 550 clock)
    repeat (650) @(posedge pclk);

    @(posedge pclk); psel = 1; penable = 0; pwrite = 0; paddr = 12'h004;
    @(posedge pclk); penable = 1;
    @(posedge pclk); #1;
    if (prdata[7:0] == 8'h5A) begin
      $display("[PASS] CASE 4: Che do 2 Stop Bits hoat dong chinh xac, nhan dung 0x5A!");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] CASE 4: LOI 2 STOP BITS! Nhan 0x%02h (mong muon 0x5A)", prdata[7:0]);
      err_cnt = err_cnt + 1;
    end
    psel = 0; penable = 0; @(posedge pclk);


    // ==========================================================
    // CASE 5: TRAN DU LIEU RX (RX OVERRUN / UNREAD BYTE PROTECTION)
    // Tinh huong: TX truyen Byte 1 (0x11). Sau do KHONG DOC 0x004.
    // Tiep tuc truyen Byte 2 (0x22).
    // Kiem tra: Phan cung xu ly Overrun nhu the nao?
    // Giu lai byte cu 0x11 (Bao ve unread) hay bi ghi de boi 0x22?
    // ==========================================================
    $display("\n--- CASE 5: TRAN DU LIEU RX (RX OVERRUN PHAN CUNG) ---");
    // Cau hinh: 8b, 1 stop, no parity
    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h008; pwdata = 32'h03; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    // Gui Byte 1 = 0x11
    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h000; pwdata = 32'h11; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);
    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h00C; pwdata = 32'h01; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    repeat (600) @(posedge pclk); // Byte 1 da vao rx_data_reg, rx_done = 1!
    $display("[INFO] Byte 1 (0x11) da den. CPU CO TINH KHONG DOC 0x004...");

    // Gui ngay Byte 2 = 0x22
    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h000; pwdata = 32'h22; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);
    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h00C; pwdata = 32'h01; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    repeat (600) @(posedge pclk); // Byte 2 da truyen xong!

    // Bay gio CPU moi doc rx_data_reg (0x004)
    @(posedge pclk); psel = 1; penable = 0; pwrite = 0; paddr = 12'h004;
    @(posedge pclk); penable = 1;
    @(posedge pclk); #1;
    if (prdata[7:0] == 8'h11) begin
      $display("[PASS] CASE 5: Phan cung su dung co che 'Keep Unread': Giu nguyen Byte cu 0x11, bo qua Byte 2 de chong mat mat!");
      pass_cnt = pass_cnt + 1;
    end else if (prdata[7:0] == 8'h22) begin
      $display("[NOTE] CASE 5: Phan cung su dung co che 'Overwrite': Byte moi 0x22 da ghi de Byte cu 0x11.");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] CASE 5: LOI BAT THUONG! Dui lieu doc ra rac: 0x%02h", prdata[7:0]);
      err_cnt = err_cnt + 1;
    end
    psel = 0; penable = 0; @(posedge pclk);


    // ==========================================================
    // CASE 6: XUNG DOT KHI GHI VAO TX DANG BAN (TX BUSY COLLISION)
    // Tinh huong: TX dang truyen byte 0xAA (chua xong).
    // CPU dot ngot ghi 0x55 va bat start_tx.
    // Kiem tra: He thong co bi treo hay khong? Co tu dong truyen byte 2 khong?
    // ==========================================================
    $display("\n--- CASE 6: XUNG DOT KHI GHI VAO TX DANG BAN (TX BUSY) ---");
    // Bat dau truyen Byte 1 = 0xAA
    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h000; pwdata = 32'hAA; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);
    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h00C; pwdata = 32'h01; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    // Cho 150 chu ky clock (TX dang truyen do dang bit 3, tx_done = 0)
    repeat (150) @(posedge pclk);

    // Kiem tra tx_done phai bang 0
    @(posedge pclk); psel = 1; penable = 0; pwrite = 0; paddr = 12'h010;
    @(posedge pclk); penable = 1;
    @(posedge pclk); #1;
    if (prdata[0] == 1'b0) begin
      $display("[INFO] Xac nhan TX dang BAN (tx_done = 0) tai giua khung truyen.");
    end
    psel = 0; penable = 0; @(posedge pclk);

    // CPU CO TINH ghi tiep byte 0x55 va bat start_tx khi TX dang ban!
    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h000; pwdata = 32'h55; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);
    @(posedge pclk); psel = 1; penable = 0; pwrite = 1; paddr = 12'h00C; pwdata = 32'h01; pstrb = 4'h1;
    @(posedge pclk); penable = 1;
    @(posedge pclk); psel = 0; penable = 0; @(posedge pclk);

    // Cho du thoi gian cho ca 2 khung (1200 clock)
    repeat (1200) @(posedge pclk);

    // Kiem tra xem RX nhan duoc byte gi va he thong co song sot khong
    @(posedge pclk); psel = 1; penable = 0; pwrite = 0; paddr = 12'h004;
    @(posedge pclk); penable = 1;
    @(posedge pclk); #1;
    $display("[RESULT] Du lieu tren RX sau xung dot TX Busy: 0x%02h", prdata[7:0]);
    if (dut.u_uart_tx.u_fsm.state == 3'b000) begin
      $display("[PASS] CASE 6: FSM TX khong bi treo, da an toan tro ve IDLE!");
      pass_cnt = pass_cnt + 1;
    end else begin
      $display("[FAIL] CASE 6: LOI NGHIEM TRONG! FSM TX bi treo o state = %b", dut.u_uart_tx.u_fsm.state);
      err_cnt = err_cnt + 1;
    end
    psel = 0; penable = 0; @(posedge pclk);

    // ==========================================================
    // TONG KET
    // ==========================================================
    $display("\n==========================================================");
    $display("TONG KET KIEM THU 6 EDGE CASES CHUYEN SAU TOAN HE THONG UART:");
    $display("SO TESTCASE THANH CONG: %0d", pass_cnt);
    $display("SO TESTCASE THAT BAI:   %0d", err_cnt);
    if (err_cnt == 0) $display("KET LUAN: >>> HE THONG UART DAT CHUAN TOT DOI VOI CAC EDGE CASES! <<<");
    else              $display("KET LUAN: >>> CO LOI CAN KHAC PHUC TRONG THIET KE! <<<");
    $display("==========================================================");

    #100;
    $finish;
  end

endmodule
