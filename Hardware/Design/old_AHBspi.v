`timescale 1ns / 1ns





// Derived from Brians UART

/*
==================================================
Pseudo-code examples:
===============================================
REMEMBER to set accelerometer to measurement mode (send SPI command to its register)
before doing anything below.
=============================================
Memory map of register addresses (HADDR[3:1]):
  0x00 = RXDATA      (read only, 16-bit data from SPI slave)
  0x02 = TXDATA      (write/read, 8-bit data to send to SPI slave)
  0x04 = STATUS      (read only, bit[0]=dataRx_ready, bit[1]=is_spi_busy)
  0x06 = CONTRL      (interrupt control: bit[0]=is_spi_busy, bit[1]=dataRx_ready)
  0x08 = CLKDELAY    (sclk = 50MHz / (2*(clkDelay+1)), default 4)
  0x0A = ENSPI       (write 1 to start TX, auto-clears on dataRx_ready)
  0x0C = FRAME       (bits per transaction: 8, 16, 24, or 32, default 32)
  0x0E = CS          (bit[0] = CS_spi, active high, drives CSn_acl low)

IMPORTANT: dataTx is 8-bit (stored_HWDATA[7:0]). Command + address must be sent
as separate byte transactions.  All examples assume byte (8-bit) frames unless
noted.

=============================================
Software for single-byte read of XDATA_L (register 0x0E):
---------------------------------------------------------
write REG_CLKDELAY = 4;          // sclk ~2.5 MHz
write REG_FRAME = 8;             // 8-bit frames
write REG_CS = 1;                // hold CS low for entire session
// TX 1: send read command (0x0B)
write REG_TXDATA = 0x0B;
write REG_ENSPI = 1;  while(STATUS.busy);
// TX 2: send starting address (0x0E)
write REG_TXDATA = 0x0E;
write REG_ENSPI = 1;  while(STATUS.busy);
// TX 3: dummy clocks → receive XDATA_L
write REG_TXDATA = 0x00;
write REG_ENSPI = 1;  while(STATUS.busy);
x_lsb = read REG_RXDATA & 0xFF;  // XDATA_L in low byte
write REG_CS = 0;                // release CS

-------------------------------------------------------------------------------------
Software for full 14-bit read of X-axis (XDATA_L + XDATA_H, registers 0x0E, 0x0F):
-------------------------------------------------------------------------------------
NOTE: The ADXL362 auto-increments the register address when CS is held low.
After reading 0x0E, the next byte comes from 0x0F.

write REG_CLKDELAY = 4;
write REG_FRAME = 8;             // 8-bit frames for cmd+addr
write REG_CS = 1;                // hold CS low
// TX 1-2: send read command + start address
write REG_TXDATA = 0x0B;  write REG_ENSPI = 1;  while(STATUS.busy);
write REG_TXDATA = 0x0E;  write REG_ENSPI = 1;  while(STATUS.busy);
// TX 3: dummy → XDATA_L
write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  while(STATUS.busy);
x_l = read REG_RXDATA & 0xFF;
// TX 4: dummy → XDATA_H (auto-incremented)
write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  while(STATUS.busy);
x_h = read REG_RXDATA & 0xFF;
x_raw = (int16)((x_h << 8) | x_l);   // assemble 16-bit signed
x_mg = x_raw >> 2;                    // 14-bit left-justified → right-justify

// Continue for Y-axis (auto-increments to 0x10, 0x11)
write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  while(STATUS.busy);
y_l = read REG_RXDATA & 0xFF;
write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  while(STATUS.busy);
y_h = read REG_RXDATA & 0xFF;
y_raw = (int16)((y_h << 8) | y_l);  y_mg = y_raw >> 2;

// Continue for Z-axis (auto-increments to 0x12, 0x13)
write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  while(STATUS.busy);
z_l = read REG_RXDATA & 0xFF;
write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  while(STATUS.busy);
z_h = read REG_RXDATA & 0xFF;
z_raw = (int16)((z_h << 8) | z_l);  z_mg = z_raw >> 2;

write REG_CS = 0;                // release CS

-----------------------------------------------------------------------------------------
Alternative: use 16-bit frame to read two bytes at once (for auto-increment pairs):
-----------------------------------------------------------------------------------------
write REG_CLKDELAY = 4;
write REG_FRAME = 8;
write REG_CS = 1;
write REG_TXDATA = 0x0B;  write REG_ENSPI = 1;  while(STATUS.busy);  // read cmd
write REG_TXDATA = 0x0E;  write REG_ENSPI = 1;  while(STATUS.busy);  // XDATA_L addr
// Now switch to 16-bit frame for data reads
write REG_FRAME = 16;
write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  while(STATUS.busy);
x_raw = (int16)read REG_RXDATA;   // {XDATA_L, XDATA_H} in one shot
x_mg = x_raw >> 2;

write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  while(STATUS.busy);
y_raw = (int16)read REG_RXDATA;  y_mg = y_raw >> 2;

write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  while(STATUS.busy);
z_raw = (int16)read REG_RXDATA;  z_mg = z_raw >> 2;
write REG_CS = 0;

----------------------------------------------------------------------------
For a write of 0x52 to SOFT_RESET (0x2C):
---------------------------------------------------------------------
write REG_FRAME = 8;
write REG_CS = 1;
write REG_TXDATA = 0x0A;  write REG_ENSPI = 1;  while(STATUS.busy);  // write cmd
write REG_TXDATA = 0x2C;  write REG_ENSPI = 1;  while(STATUS.busy);  // SOFT_RESET addr
write REG_TXDATA = 0x52;  write REG_ENSPI = 1;  while(STATUS.busy);  // data byte
write REG_CS = 0;

-----------------------------------------------------------------------------------------
Interrupt-driven alternative for multi-byte reads (no busy-waiting):
-----------------------------------------------------------------------------------------
// CONTRL register: bit[0] = enable IRQ on is_spi_busy, bit[1] = enable IRQ on dataRx_ready
// For this example, enable only dataRx_ready (fires once per completed frame).
// The ISR uses a state machine to sequence the bytes.

reg [2:0] spi_step;  // tracks which byte we are on in the session

// Setup (run once):
write REG_CLKDELAY = 4;
write REG_FRAME = 8;
write REG_CS = 1;                    // hold CS low for session
write REG_CONTRL = 2'b10;           // enable interrupt on dataRx_ready only
spi_step = 0;

// Kick off first byte:
write REG_TXDATA = 0x0B;            // read command
write REG_ENSPI = 1;                // start TX, interrupt fires when done
// ← CPU is free to do other work here, SPI runs in background

// Interrupt service routine (read 6 bytes: XL, XH, YL, YH, ZL, ZH):
on spi_IRQ:
    data = read REG_RXDATA;          // byte from the TX that just completed
    spi_step = spi_step + 1;         // next TX to send
    // data arrives one TX after its dummy was sent (ADXL362 pipeline)
    case (spi_step):
        1:  write REG_TXDATA = 0x0E;  write REG_ENSPI = 1;  // address byte
        2:  write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  // dummy → XDATA_L
        3:  x_l = data;  write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  // dummy → XDATA_H
        4:  x_h = data;  write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  // dummy → YDATA_L
        5:  y_l = data;  write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  // dummy → YDATA_H
        6:  y_h = data;  write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  // dummy → ZDATA_L
        7:  z_l = data;  write REG_TXDATA = 0x00;  write REG_ENSPI = 1;  // dummy → ZDATA_H
        8:  z_h = data;  write REG_CS = 0;  write REG_CONTRL = 0;  // done
            x_raw = (x_h << 8) | x_l;  y_raw = (y_h << 8) | y_l;  z_raw = (z_h << 8) | z_l;
    endcase
*/



//////////////////////////////////////////////////////////////////////////////////
// Company: UCD School of Electrical and Electronic Engineering
// Engineer: Brian Mulkeen, with fifo blocks from ARM
// 
// Create Date:   20 October 2014 
// Design Name: 	Cortex-M0 DesignStart system
// Module Name:   AHBuart 
// Description: 	Provides asynchronous serial transmitter and receiver on AHB.
//					Transmit and receive paths have 16-byte FIFO buffers.
//		Address 0 - receive data, 8 bits, from FIFO, read only
//		Address 4 - transmit data, 8-bits, to FIFO (read gives FIFO output)
//		Address 8 - status, read only: 	bit 0 = tx FIFO full
//										bit 1 = tx FIFO empty
//										bit 2 = rx FIFO full
//										bit 3 = rx FIFO not empty - data available
//		Address C - control - four interrupt enable bits, 1 enables corresponding status
//					bit to cause interrupt, 0 blocks the interrupt (default).
//		This version provides simple level-based interrupt signal from the status bits.
//		The only way to clear an interrupt request is to remove the problem or clear the enable bit.
//		All transfers 32 bits, with data bits right-justified, filled with 0 on left on read.
// Revision: 
// Revision 0.01 - File Created
// Revision 1 - modified for synchronous reset, October 2015
// Revision 2 - added HRESP output, March 2024
//
//////////////////////////////////////////////////////////////////////////////////
module AHBspi(
			// Bus signals
			input  HCLK,			// bus clock
			input  HRESETn,			// bus reset, active low
			input  HSEL,			// selects this slave
			input  HREADY,			// indicates previous transaction completing
			input  [31:0] HADDR,	// address
			input  [1:0] HTRANS,	// transaction type (only bit 1 used)
			input  HWRITE,			// write transaction
//			input  [2:0] HSIZE,		// transaction width ignored
			input  [31:0] HWDATA,	// write data
			output [31:0] HRDATA,	// read data from slave
			output HREADYOUT,		// ready output from slave
			output HRESP,			// response output from slave
			// SPI signals
			input miso,			// SPI slave output
			output mosi,		// Spi master output
			output CSn_acl, // acceleromiter select (only one slave)
			output spi_IRQ,			// interrupt request
			output sclk
    );
	
	// Registers to hold signals from address phase
	reg [2:0] rHADDR;			// for storing register adress
	reg rWrite; // write enable signal
	//reg rRead;	// read enable signal

	// Internal signals
	reg [15:0]	readData;		// 16-bit data from read multiplexer
	//wire [7:0] rx_fifo_out, rx_fifo_in, tx_fifo_out;  // fifo data
	//wire rx_fifo_empty, rx_fifo_full, tx_fifo_empty, tx_fifo_full;  // fifo output signals
	//wire tx_fifo_wr = rWrite & (rHADDR == 2'h1);  // tx fifo write on write to address 0x4
	//wire rx_fifo_rd = rRead & (rHADDR == 2'h0);  // rx fifo read on read to address 0x0
	//wire txrdy;		// transmitter status signal
	//wire txgo = ~tx_fifo_empty;	// transmitter control signal
	//wire rxnew;		// receiver strobe output
	wire dataRx_ready;
	wire [15:0] dataRx; // data recived from the spi slave
	wire [7:0] dataTx; // Data to send to slave
	wire is_spi_busy; // high if spi is busy
	reg [7:0] stored_HWDATA; // stores data to send to slave
	
	// Write enables
	// The block captures only HADDR[3:1] (bits 3:1 of the address bus) into rHADDR. 
    wire tx_slave_wr = rWrite & (rHADDR == 3'h1);  // tx slave write on, write to address 0x2
    wire IRQcontrol_wr = rWrite && (rHADDR == 3'h3); // set eqivelent bits to 0 to disable interupt for the equivelent flag
    wire clkDelay_wr = rWrite & (rHADDR == 3'h4); // write to clkDelay register (address 0x8)
    wire enSpi_wr = rWrite & (rHADDR == 3'd5); // write to spi enable 0xA
    wire frame_wr = rWrite & (rHADDR == 3'd6); // write enable
    wire csSpi_wr = rWrite & (rHADDR == 3'd7); // spi slave select (for acceleromiter as there is only 1) 

 	// Capture bus signals in address phase
	always @(posedge HCLK)
		if(!HRESETn)
			begin
				rHADDR <= 3'b0;
				rWrite <= 1'b0;
				//rRead  <= 1'b0;
			end
		else if(HREADY)
		 begin
			rHADDR <= HADDR[3:1];         // capture address bits for for use in data phase
			rWrite <= HSEL & HWRITE & HTRANS[1];	// slave selected for write transfer       
			//rRead <= HSEL & ~HWRITE & HTRANS[1];	// slave selected for read transfer 
		 end
		 
    // Capture Tx data (only allowed if spi is not busy)
    always @ (posedge HCLK)
        if (!HRESETn) stored_HWDATA <= 8'b0;
        else if (tx_slave_wr && !is_spi_busy) stored_HWDATA <= HWDATA[7:0]; // only takes 8 bits
        else stored_HWDATA <= stored_HWDATA;
        

	// Control register
	reg [1:0] control;	// holds interrupt enable bits
	always @(posedge HCLK)
		if (!HRESETn) control <= 2'b0;
		else if (IRQcontrol_wr) control <= HWDATA[1:0];
		else control <= control;
		
	// Status bits - can read in status register, can cause interrupts if enabled
	wire status = {dataRx_ready, is_spi_busy};
	
	// Interrupt signal - AND each status bit with enable bit, then OR all the results
	assign spi_IRQ = |(status & control);
		
		
    // Clock delay register
        // SCLK = 50MHz / (2 * (clkDelay + 1)) (Note: the bits are actually shifted NOT divided)
        // Acceleromiter max clock speed is 5MHZ, clkDelay = 4 
    reg [3:0] clkDelay;
    //assign clkDelay = 4'd9;
    always @ (posedge HCLK)
       if (!HRESETn) clkDelay <= 4'd4; // cant set to zero as would make a sclk 50MHz, accelerometer has a max sclk speed of 5MHz.
       else if (clkDelay_wr) clkDelay <= HWDATA[3:0]; 
       else clkDelay <= clkDelay;
       
    // Spi Enable Register 
    reg en_spi;
    always @ (posedge HCLK)
        if (!HRESETn) en_spi <= 1'b0;
        else if (enSpi_wr) en_spi <= HWDATA[0];
        else if (en_spi && !dataRx_ready) en_spi <= en_spi;
        else en_spi <= 1'b0;
        //else en_spi <= en_spi;
        
        
    // Transaction frame control 
    //  WRITE: command = 0x0A, 16 bits needed [command byte (8 bits) + data byte (8 bits)]
    //  READ: command = 0x0B, 32 bits needed [command byte (8) + address byte (8) + response byte (16)]
    reg [5:0] frameBits; // Bits needed to complete a transaction 
    always @ (posedge HCLK)
        if (!HRESETn) frameBits <= 6'd32; // Defaults to 32 bits
        else if (frame_wr) frameBits <= HWDATA[6:0];
        else frameBits <= frameBits;
        
    // Spi slave select control 
    // CS_spi
    reg CS_spi; // active high
    always @ (posedge HCLK)
        if (!HRESETn) CS_spi <= 1'b0;
        else if (csSpi_wr) CS_spi <= HWDATA[0];
        else CS_spi <= CS_spi;
        
    assign CSn_acl = ~CS_spi;
       
	// Bus output signals
	always @*  // auto-sensitivity (includes all signals read in this block)
		case (rHADDR)		// select on word address (stored from address phase)
			3'h0:		readData = dataRx;	// read from rx from slave, updates after each completed spi tansaction
			3'h1:		readData = {8'b0, stored_HWDATA};	// read of tx data being sent to slave
			3'h2:		readData = {14'b0, status};	// status register	    
			3'h3:		readData = {14'b0, control};	// read back of control register
			3'h4:       readData = {12'b0, clkDelay}; // read current clock dealy
			3'h5:       readData = {15'b0, en_spi}; // read the sly enable
			3'h6:       readData = {10'b0, frameBits}; // read the frameBits reg
			3'h7:       readData = {15'b0, CS_spi}; // read spi slave select (acceleromiter select) active high
			default:    readData = 16'hdead;
		endcase
		
	assign HRDATA = {16'b0, readData};	// extend with 0 bits for bus read

	assign HREADYOUT = 1'b1;	// always ready
	assign HRESP = 1'b0;		// always OKAY
    


	

	   
	   
// ====================== SPI ==================
// TODO Add missign signals for lower SPI module: 
//   .tx_begin        (BEGIN_spi),// put high when want to start tx
//   .clkDelay        (CLKDELAY_spi),// sclk = 50MHZ/(clkDelay + 1) [4 bits]
//    .dataRx          (dataRx) // 16 bit result from SPI slave
//    .dataRx_ready    (dataRx_ready) // flag to say data from SPI slave is re



    spi spi2(
   // ==== Software control Inputs ===
   
   // == SPI signals ==
   // Inputs 
    .miso            (miso),
   // Outputs
    .sclk            (sclk),
    .mosi            (mosi),
    //.cs_bar_accel    (CSn_acl),
    
   // == ABH-lite Signals ==
   // Inputs
   .clk             (HCLK),             // bus clock
   .dataTx          (stored_HWDATA), // byte to transmit to SPI slave
   .reset_spi       (HRESETn),// syncrinus spi rest (active low) // Right now i have it on the AHB-lite bus reset
   .tx_begin        (en_spi),// put high when want to start tx
   .clkDelay        (clkDelay),// sclk = 50MHZ/(clkDelay + 1) [4 bits]
  
  // Outputs
   .dataRx          (dataRx), // 16 bit result from SPI slave
   .dataRx_ready    (dataRx_ready), // flag to say data from SPI slave is ready
   .is_spi_busy     (is_spi_busy), // sending if 1 
   .frameBits       (frameBits) // bits needed for a completed transaction 
   );
   
   
   

endmodule

