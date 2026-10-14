import sys

class EdgeSim:
    def __init__(self):
        # Globals
        self.clk = 0
        self.rst_n = 1
        
        # Baudrate (50MHz, 1MHz -> D_RX=3, D_TX=48)
        self.D_RX = 3
        self.D_TX = 48
        self.cnt_tx = 0
        self.cnt_rx = 0
        self.tx_tick = 0
        self.rx_tick = 0
        
        # APB bus
        self.psel = 0
        self.penable = 0
        self.pwrite = 0
        self.paddr = 0
        self.pwdata = 0
        self.pstrb = 0
        self.prdata = 0
        
        # APB registers
        self.tx_data_reg = 0
        self.cfg_reg = 0
        self.ctrl_reg = 0
        self.rx_data_reg = 0
        
        # APB FSM
        self.apb_state = 0 # 0: IDLE, 1: SETUP, 2: ACCESS
        self.reg_wr_en = 0
        self.reg_rd_en = 0
        
        # TX FSM & Datapath
        self.tx_state = 0 # 0:IDLE, 1:START, 2:DATA, 3:PARITY, 4:STOP
        self.start_pending = 0
        self.tx_bit_cnt = 0
        self.tx_stop_cnt = 0
        self.tx_shift_reg = 0xFF
        self.tx = 1
        self.tx_done = 1
        
        # RX Controller & Datapath
        self.rx_state = 0 # 0:IDLE, 1:START, 2:DATA, 3:PARITY, 4:STOP1, 5:STOP2
        self.rx_ff1 = 1
        self.rx_s = 1
        self.os_cnt = 0
        self.rx_bit_cnt = 0
        self.rx_sh = 0
        self.parity_acc = 0
        self.frame_parity_error = 0
        self.rx_data = 0
        self.rx_done = 0
        self.parity_error = 0
        
        # Testbench overrides
        self.rx_override = 0
        self.rx_drv = 1

    def step(self):
        # 1. Baudrate generator
        if not self.rst_n:
            self.cnt_tx = 0
            self.tx_tick = 0
            self.cnt_rx = 0
            self.rx_tick = 0
        else:
            if self.cnt_tx == self.D_TX - 1:
                self.cnt_tx = 0
                self.tx_tick = 1
            else:
                self.cnt_tx += 1
                self.tx_tick = 0
                
            if self.cnt_rx == self.D_RX - 1:
                self.cnt_rx = 0
                self.rx_tick = 1
            else:
                self.cnt_rx += 1
                self.rx_tick = 0
                
        # 2. RX input
        rx_in = self.rx_drv if self.rx_override else self.tx
        if not self.rst_n:
            self.rx_ff1 = 1
            self.rx_s = 1
        else:
            self.rx_ff1 = rx_in
            self.rx_s = self.rx_ff1
            
        # Config decoded
        data_bit_num = self.cfg_reg & 0x3
        stop_bit_num = (self.cfg_reg >> 2) & 0x1
        parity_en = (self.cfg_reg >> 3) & 0x1
        parity_type = (self.cfg_reg >> 4) & 0x1
        
        # 3. APB FSM
        addr_match = self.paddr in [0x0, 0x4, 0x8, 0xC, 0x10]
        if not self.rst_n:
            self.apb_state = 0
            self.reg_wr_en = 0
            self.reg_rd_en = 0
        else:
            if self.apb_state == 0: # IDLE
                if self.psel:
                    self.apb_state = 1 # SETUP
                self.reg_wr_en = 0
                self.reg_rd_en = 0
            elif self.apb_state == 1: # SETUP
                if self.penable:
                    self.apb_state = 2 # ACCESS
                    self.reg_wr_en = 1 if (self.pwrite and addr_match) else 0
                    self.reg_rd_en = 1 if ((not self.pwrite) and addr_match) else 0
                else:
                    self.reg_wr_en = 0
                    self.reg_rd_en = 0
            elif self.apb_state == 2: # ACCESS
                self.apb_state = 0 # IDLE
                self.reg_wr_en = 0
                self.reg_rd_en = 0
                
        # APB Datapath write
        start_tx_pulse = 0
        clear_rx_done = 1 if (self.paddr == 0x4 and self.reg_rd_en) else 0
        
        if not self.rst_n:
            self.tx_data_reg = 0
            self.cfg_reg = 0
            self.ctrl_reg = 0
            self.rx_data_reg = 0
        else:
            if self.reg_wr_en and (self.pstrb & 0x1):
                if self.paddr == 0x0:
                    self.tx_data_reg = self.pwdata & 0xFF
                elif self.paddr == 0x8:
                    self.cfg_reg = self.pwdata
                elif self.paddr == 0xC:
                    self.ctrl_reg = self.pwdata
                    start_tx_pulse = self.ctrl_reg & 0x1
            else:
                self.ctrl_reg &= ~1 # pulse bit 0 clears next cycle
                
            if self.rx_done:
                self.rx_data_reg = self.rx_data & 0xFF
                
        # APB Read MUX
        stt_reg = (self.parity_error << 2) | (self.rx_done << 1) | (self.tx_done & 1)
        if self.reg_rd_en:
            if self.paddr == 0x0: self.prdata = self.tx_data_reg
            elif self.paddr == 0x8: self.prdata = self.cfg_reg
            elif self.paddr == 0xC: self.prdata = self.ctrl_reg
            elif self.paddr == 0x4: self.prdata = self.rx_data_reg
            elif self.paddr == 0x10: self.prdata = stt_reg
            else: self.prdata = 0
        else:
            self.prdata = 0
            
        # 4. TX FSM & Datapath
        start_req = start_tx_pulse or self.start_pending
        if not self.rst_n:
            self.start_pending = 0
        else:
            if start_tx_pulse:
                self.start_pending = 1
            elif self.tx_state == 0 and start_req and self.tx_tick:
                self.start_pending = 0
                
        # TX Datapath limits
        max_val_tx = [4, 5, 6, 7][data_bit_num]
        max_stop_val_tx = 2 if stop_bit_num else 1
        
        bit_last_tx = (self.tx_bit_cnt == max_val_tx)
        stop_last_tx = (self.tx_stop_cnt == max_stop_val_tx - 1)
        
        # Parity calc
        masks = [0x1F, 0x3F, 0x7F, 0xFF]
        masked = self.tx_data_reg & masks[data_bit_num]
        ones = bin(masked).count('1')
        even_parity = ones % 2
        tx_parity_bit = even_parity if parity_type else (1 - even_parity)
        
        # Next state tx
        nxt_tx_state = self.tx_state
        load_reg_tx = 0
        shift_reg_tx = 0
        clr_bit_tx = 1
        clr_stop_tx = 1
        
        if self.tx_state == 0: # IDLE
            if start_req and self.tx_tick:
                nxt_tx_state = 1 # START
                load_reg_tx = 1
        elif self.tx_state == 1: # START
            if self.tx_tick:
                nxt_tx_state = 2 # DATA
        elif self.tx_state == 2: # DATA
            clr_bit_tx = 0
            if not bit_last_tx and self.tx_tick:
                shift_reg_tx = 1
            elif bit_last_tx and self.tx_tick and parity_en:
                nxt_tx_state = 3 # PARITY
            elif bit_last_tx and self.tx_tick and not parity_en:
                nxt_tx_state = 4 # STOP
        elif self.tx_state == 3: # PARITY
            if self.tx_tick:
                nxt_tx_state = 4 # STOP
        elif self.tx_state == 4: # STOP
            clr_stop_tx = 0
            if stop_last_tx and self.tx_tick:
                nxt_tx_state = 0 # IDLE
                
        # TX outputs
        if self.tx_state == 0:
            self.tx_done = 0 if start_req else 1
            self.tx = 1
        elif self.tx_state == 1:
            self.tx_done = 0
            self.tx = 0
        elif self.tx_state == 2:
            self.tx_done = 0
            self.tx = self.tx_shift_reg & 1
        elif self.tx_state == 3:
            self.tx_done = 0
            self.tx = tx_parity_bit
        elif self.tx_state == 4:
            self.tx_done = 0
            self.tx = 1
            
        # TX Sequential update
        if not self.rst_n:
            self.tx_state = 0
            self.tx_bit_cnt = 0
            self.tx_stop_cnt = 0
            self.tx_shift_reg = 0xFF
        else:
            self.tx_state = nxt_tx_state
            if load_reg_tx:
                self.tx_shift_reg = self.tx_data_reg
            elif shift_reg_tx:
                self.tx_shift_reg = (self.tx_shift_reg >> 1) | 0x80
                
            if clr_bit_tx:
                self.tx_bit_cnt = 0
            elif self.tx_tick:
                self.tx_bit_cnt += 1
                
            if clr_stop_tx:
                self.tx_stop_cnt = 0
            elif self.tx_tick:
                self.tx_stop_cnt += 1
                
        # 5. RX Controller & Datapath
        os_mid = (self.os_cnt == 7)
        os_last = (self.os_cnt == 15)
        bit_last_rx = (self.rx_bit_cnt == max_val_tx)
        expected_parity = self.parity_acc if parity_type else (1 - self.parity_acc)
        
        nxt_rx_state = self.rx_state
        os_clear = 0
        os_inc = 0
        bit_clear = 0
        bit_inc = 0
        frame_clear = 0
        sample_en = 0
        parity_check = 0
        stop_check = 0
        latch_en = 0
        
        if self.rx_tick:
            if self.rx_state == 0: # IDLE
                os_clear = 1
                if not self.rx_s:
                    nxt_rx_state = 1 # START
            elif self.rx_state == 1: # START
                if not os_mid:
                    os_inc = 1
                else:
                    os_clear = 1
                    if self.rx_s:
                        nxt_rx_state = 0 # false start
                    else:
                        bit_clear = 1
                        frame_clear = 1
                        nxt_rx_state = 2 # DATA
            elif self.rx_state == 2: # DATA
                if not os_last:
                    os_inc = 1
                else:
                    os_clear = 1
                    sample_en = 1
                    if bit_last_rx:
                        nxt_rx_state = 3 if parity_en else 4 # PARITY or STOP1
                    else:
                        bit_inc = 1
            elif self.rx_state == 3: # PARITY
                if not os_last:
                    os_inc = 1
                else:
                    os_clear = 1
                    parity_check = 1
                    nxt_rx_state = 4 # STOP1
            elif self.rx_state == 4: # STOP1
                if not os_last:
                    os_inc = 1
                else:
                    os_clear = 1
                    stop_check = 1
                    if not self.rx_s:
                        nxt_rx_state = 0
                    elif stop_bit_num:
                        nxt_rx_state = 5 # STOP2
                    else:
                        latch_en = 1
                        nxt_rx_state = 0
            elif self.rx_state == 5: # STOP2
                if not os_last:
                    os_inc = 1
                else:
                    os_clear = 1
                    stop_check = 1
                    latch_en = self.rx_s
                    nxt_rx_state = 0
                    
        # RX Sequential update
        if not self.rst_n:
            self.rx_state = 0
            self.os_cnt = 0
            self.rx_bit_cnt = 0
            self.rx_sh = 0
            self.parity_acc = 0
            self.frame_parity_error = 0
            self.rx_data = 0
            self.rx_done = 0
            self.parity_error = 0
        else:
            self.rx_state = nxt_rx_state
            if clear_rx_done:
                self.rx_done = 0
                self.parity_error = 0
                
            if os_clear:
                self.os_cnt = 0
            elif os_inc:
                self.os_cnt += 1
                
            if bit_clear:
                self.rx_bit_cnt = 0
            elif bit_inc:
                self.rx_bit_cnt += 1
                
            if frame_clear:
                self.rx_sh = 0
                self.parity_acc = 0
                self.frame_parity_error = 0
            elif sample_en:
                self.rx_sh = (self.rx_sh & ~(1 << self.rx_bit_cnt)) | (self.rx_s << self.rx_bit_cnt)
                self.parity_acc ^= self.rx_s
                
            if parity_check:
                self.frame_parity_error = 1 if (self.rx_s != expected_parity) else 0
                
            if latch_en and (not self.rx_done or clear_rx_done):
                self.rx_data = self.rx_sh
                self.rx_done = 1
                self.parity_error = self.frame_parity_error

sim = EdgeSim()

def apb_write(addr, data):
    # Setup
    sim.psel = 1; sim.penable = 0; sim.pwrite = 1; sim.paddr = addr; sim.pwdata = data; sim.pstrb = 1
    sim.step()
    # Access
    sim.penable = 1
    sim.step()
    # Idle
    sim.psel = 0; sim.penable = 0
    sim.step()

def apb_read(addr):
    # Setup
    sim.psel = 1; sim.penable = 0; sim.pwrite = 0; sim.paddr = addr
    sim.step()
    # Access
    sim.penable = 1
    sim.step()
    val = sim.prdata
    # Idle
    sim.psel = 0; sim.penable = 0
    sim.step()
    return val

def wait_clocks(n):
    for _ in range(n):
        sim.step()

print("--- Running Testbench Cases ---")

# Reset
sim.rst_n = 0
wait_clocks(5)
sim.rst_n = 1
wait_clocks(5)

# Case 1: Parity Error
apb_write(0x8, 0x1B) # 8b, 1 stop, Parity Even
# Send byte 0x3C with parity 1 (error)
sim.rx_override = 1
sim.rx_drv = 0 # start
wait_clocks(50)
for b in [0,0,1,1,1,1,0,0]: # 0x3C LSB first
    sim.rx_drv = b
    wait_clocks(50)
sim.rx_drv = 1 # bad parity (even of 4 ones is 0, we send 1)
wait_clocks(50)
sim.rx_drv = 1 # stop
wait_clocks(50)
sim.rx_override = 0
wait_clocks(100)
stt = apb_read(0x10)
p_err = (stt >> 2) & 1
print(f"CASE 1: parity_error = {p_err} (expected 1)")
apb_read(0x4) # clear

# Case 2: False start glitch
sim.rx_override = 1
sim.rx_drv = 0
wait_clocks(5)
sim.rx_drv = 1
sim.rx_override = 0
wait_clocks(600)
stt = apb_read(0x10)
rx_done = (stt >> 1) & 1
print(f"CASE 2.1: rx_done after glitch = {rx_done} (expected 0)")

# Case 2.2: Send 0x99
apb_write(0x8, 0x03)
apb_write(0x0, 0x99)
apb_write(0xC, 0x01)
wait_clocks(600)
data = apb_read(0x4)
print(f"CASE 2.2: data = 0x{data:02X} (expected 0x99)")

# Case 3: 5-bit mode
apb_write(0x8, 0x00) # 5b, 1 stop, no parity
apb_write(0x0, 0xFF)
apb_write(0xC, 0x01)
wait_clocks(500)
data = apb_read(0x4)
print(f"CASE 3: 5-bit data = 0x{data:02X} (expected 0x1F)")

# Case 4: 2 Stop bits
apb_write(0x8, 0x07) # 8b, 2 stop, no parity
apb_write(0x0, 0x5A)
apb_write(0xC, 0x01)
wait_clocks(650)
data = apb_read(0x4)
print(f"CASE 4: 2 stop bits data = 0x{data:02X} (expected 0x5A)")

# Case 5: Overrun
apb_write(0x8, 0x03)
apb_write(0x0, 0x11)
apb_write(0xC, 0x01)
wait_clocks(600)
# Send byte 2 without reading
apb_write(0x0, 0x22)
apb_write(0xC, 0x01)
wait_clocks(600)
data = apb_read(0x4)
print(f"CASE 5: data = 0x{data:02X} (expected 0x11 or 0x22)")

# Case 6: TX collision
apb_write(0x0, 0xAA)
apb_write(0xC, 0x01)
wait_clocks(150)
apb_write(0x0, 0x55)
apb_write(0xC, 0x01)
wait_clocks(1200)
data = apb_read(0x4)
print(f"CASE 6: final rx data = 0x{data:02X}")
