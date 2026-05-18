`timescale 1ns / 1ns

module TB_AHBspi (    );

// AHB-Lite Bus Signals
	reg HCLK;					// bus clock
	reg HRESETn;				// bus reset, active low
	reg HSELx = 1'b0;			// selects this slave
	reg [31:0] HADDR = 32'h0;	// address
	reg [1:0] HTRANS = 2'b0;	// transaction type (only two tpyes used)
	reg HWRITE = 1'b0;			// write transaction
	reg [2:0] HSIZE = 3'b0;		// transaction width (max 32-bit supported)
	reg [31:0] HWDATA = 32'h0;	// write data
	wire [31:0] HRDATA;			// read data from slave
    wire HREADY;             	// ready signal - to master and to all slaves
    wire HREADYOUT;             // ready signal output from this slave

// Other signals to connect to the module under test
	wire miso, mosi, CSn_acl, spi_IRQ, sclk;
	assign miso = mosi;  // loopback: DUT's mosi output feeds miso input


// Integer is used in for loops
	integer i = 0;

// Define names for some of the bus signal values and for device register addresses
	localparam [2:0] BYTE = 3'b000, HALF = 3'b001, WORD = 3'b010;	// HSIZE values
	localparam [1:0] IDLE = 2'b00, NONSEQ = 2'b10;					// HTRANS values
	localparam [31:0] RXDATA = 32'h5300_0000, TXDATA = 32'h5300_0002, 
	                   STATUS = 32'h5300_0004, CONTRL = 32'h5300_0006,
	                   CLKDELAY = 32'h5300_0008, ENSPI = 32'h5300_000A,
	                   FRAME = 32'h5300_000C, CS = 32'h5300_000E;	// registers

// Instantiate the design under test and connect it to the testbench signals
// Some bus signals are not used - this design ignores HSIZE, for example
	AHBspi dut(
		.HCLK(HCLK),
		.HRESETn(HRESETn),
		.HSEL(HSELx),
		.HREADY(HREADY),
		.HADDR(HADDR),
		.HTRANS(HTRANS),
		.HWRITE(HWRITE),  
		.HWDATA(HWDATA),  
		.HRDATA(HRDATA),  
		.HREADYOUT(HREADYOUT),
	    // SPI signals
        .miso(miso),            // SPI slave output
        .mosi(mosi),        // Spi master output
        .CSn_acl(CSn_acl), // acceleromiter select (only one slave)
        .spi_IRQ(spi_IRQ),            // interrupt request
        .sclk(sclk)
		);

// Generate the clock signal at 50 MHz - period 20 ns
	initial
		begin
			HCLK = 1'b0;
			forever
				#10 HCLK = ~HCLK;  // invert clock every 10 ns
		end

// Log file for offline review
integer log_fd;

// Generate reset pulse and simulate bus transactions for the SPI slave.
// Registers (HADDR[3:1]): 0=RXDATA, 1=TXDATA, 2=STATUS, 3=CONTRL,
//                         4=CLKDELAY, 5=ENSPI, 6=FRAME, 7=CS
// Loopback: miso = mosi (wired at top of testbench) → data sent is received back.
//   8-bit frame: shiftReg right-rotate by 8 → original dataTx appears in dataRx[7:0]
//  16-bit frame: shiftReg right-rotate by 16 → original {dataTx, 8'b0} in dataRx
//
// Note: AHBspi captures HWDATA[7:0] directly (ignores HSIZE and addr[1:0] byte lanes).
//   So all writes use WORD to ensure data lands on HWDATA[7:0] regardless of address.
//   All reads also use WORD so the comparison sees the full 32-bit HRDATA.
	initial
		begin
			log_fd = $fopen("TB_AHBspi_log.txt", "w");
			$fdisplay(log_fd, "===== TB_AHBspi Simulation Log =====");
			$fdisplay(log_fd, "Time\t\tEvent\t\t\t\tDetails");
			$fdisplay(log_fd, "----\t\t-----\t\t\t\t-------");

			HRESETn = 1'b1;
			#20 HRESETn = 1'b0;
			#20 HRESETn = 1'b1;		// release reset
			#50;
			$fdisplay(log_fd, "%0t\tReset done\t\t\tclkDelay=%0d  frameBits=%0d  CS=%b",
				$time, dut.clkDelay, dut.frameBits, dut.CS_spi);

			// =========== Test 1: Register write/readback ===========
			$fdisplay(log_fd, "\n--- Test 1: Register write/readback ---");
			AHBwrite(WORD, CLKDELAY, 16'd7);
			AHBidle;
			$fdisplay(log_fd, "%0t\tWrote CLKDELAY=7", $time);
			AHBread(WORD, CLKDELAY, 16'd7);
			AHBidle;
			$fdisplay(log_fd, "%0t\tRead  CLKDELAY=%0d (expect 7)", $time, dut.clkDelay);

			AHBwrite(WORD, FRAME, 16'd16);
			AHBidle;
			$fdisplay(log_fd, "%0t\tWrote FRAME=16", $time);
			AHBread(WORD, FRAME, 16'd16);
			AHBidle;
			$fdisplay(log_fd, "%0t\tRead  FRAME=%0d (expect 16)", $time, dut.frameBits);

			AHBwrite(WORD, CS, 8'd1);
			AHBidle;
			$fdisplay(log_fd, "%0t\tWrote CS=1", $time);
			AHBread(WORD, CS, 8'd1);
			AHBidle;
			$fdisplay(log_fd, "%0t\tRead  CS=%b (expect 1)  CSn_acl=%b", $time, dut.CS_spi, CSn_acl);
			AHBwrite(WORD, CS, 8'd0);
			AHBidle;
			$fdisplay(log_fd, "%0t\tWrote CS=0  CSn_acl=%b", $time, CSn_acl);

			// =========== Test 2: 8-bit SPI loopback ===========
			$fdisplay(log_fd, "\n--- Test 2: 8-bit SPI loopback ---");
			AHBwrite(WORD, CLKDELAY, 16'd4);
			AHBidle;
			AHBwrite(WORD, FRAME, 16'd8);
			AHBidle;
			AHBwrite(WORD, CS, 8'd1);
			AHBidle;
			$fdisplay(log_fd, "%0t\tSetup: clkDelay=4  FRAME=8  CS=1  CSn_acl=%b", $time, CSn_acl);

			AHBwrite(WORD, TXDATA, 8'hA5);
			AHBidle;
			// Wait 1 extra cycle for stored_HWDATA to update via NBA, then verify
			#40;
			$fdisplay(log_fd, "%0t\tTXDATA <= 0xA5  stored_HWDATA=0x%h (expect A5)", $time, dut.stored_HWDATA);
			AHBread(WORD, TXDATA, 8'hA5);	// confirm TXDATA write took effect
			AHBidle;
			$fdisplay(log_fd, "%0t\tTXDATA readback HRDATA=0x%h (expect 0xA5)  stored_HWDATA=0x%h",
				$time, HRDATA, dut.stored_HWDATA);

			AHBwrite(WORD, ENSPI, 8'd1);
			AHBidle;	// let SPI reach TX state before reading STATUS
			// State machine: IDLE(0) → PREP(1) → TX(2) → COMPLETE(3) → IDLE
			$fdisplay(log_fd, "%0t\tENSPI=1  state=%0d  is_spi_busy=%b  sclk=%b  mosi=%b  stored_HWDATA=0x%h",
				$time, dut.spi2.currentState, dut.spi2.is_spi_busy, sclk, mosi, dut.stored_HWDATA);

			// Read STATUS during TX — is_spi_busy=1 → status={0,1}=1
			AHBread(WORD, STATUS, 8'h01);	// status = {dataRx_ready, is_spi_busy}
			AHBidle;
			$fdisplay(log_fd, "%0t\tSTATUS=0x%h (expect 1=busy)  state=%0d  countBit=%0d  shiftReg=0x%h",
				$time, HRDATA, dut.spi2.currentState, dut.spi2.countBit, dut.spi2.shiftReg);

			// Wait for 8-bit transaction to complete (~1.6us at clkDelay=4)
			#5000;
			$fdisplay(log_fd, "%0t\tAfter wait:  state=%0d  countBit=%0d  shiftReg=0x%h  dataRx=0x%h  dataRx_ready=%b",
				$time, dut.spi2.currentState, dut.spi2.countBit, dut.spi2.shiftReg,
				dut.spi2.dataRx, dut.spi2.dataRx_ready);

			// Read STATUS after completion — expect busy=0
			AHBread(WORD, STATUS, 8'h00);
			AHBidle;
			$fdisplay(log_fd, "%0t\tSTATUS=0x%h (expect 0=idle)", $time, HRDATA);

			// Read RXDATA — loopback: 0x00A5
			AHBread(WORD, RXDATA, 16'h00A5);
			AHBidle;
			$fdisplay(log_fd, "%0t\tRXDATA=0x%h (expect 0x00A5)", $time, HRDATA);

			AHBwrite(WORD, CS, 8'd0);
			AHBidle;

			// =========== Test 3: 16-bit SPI loopback ===========
			$fdisplay(log_fd, "\n--- Test 3: 16-bit SPI loopback ---");
			AHBwrite(WORD, FRAME, 16'd16);
			AHBidle;
			AHBwrite(WORD, CS, 8'd1);
			AHBidle;
			AHBwrite(WORD, TXDATA, 8'h5A);
			AHBidle;
			$fdisplay(log_fd, "%0t\tTXDATA <= 0x5A  stored_HWDATA=0x%h  FRAME=%0d", $time, dut.stored_HWDATA, dut.frameBits);
			AHBwrite(WORD, ENSPI, 8'd1);
			AHBidle;	// let SPI reach TX state
			$fdisplay(log_fd, "%0t\tENSPI=1  state=%0d  is_spi_busy=%b", $time, dut.spi2.currentState, dut.spi2.is_spi_busy);

			// Confirm busy during TX
			AHBread(WORD, STATUS, 8'h02);
			AHBidle;

			// Wait for 16-bit transaction to complete (~3.2us)
			#10000;
			$fdisplay(log_fd, "%0t\tAfter wait:  state=%0d  countBit=%0d  shiftReg=0x%h  dataRx=0x%h",
				$time, dut.spi2.currentState, dut.spi2.countBit, dut.spi2.shiftReg,
				dut.spi2.dataRx);

			// Loopback: shiftReg right-rotate by 16 → 0x5A00
			AHBread(WORD, RXDATA, 16'h5A00);
			AHBidle;
			$fdisplay(log_fd, "%0t\tRXDATA=0x%h (expect 0x5A00)", $time, HRDATA);

			AHBwrite(WORD, CS, 8'd0);
			AHBidle;

			// =========== Test 4: Interrupt on dataRx_ready ===========
			$fdisplay(log_fd, "\n--- Test 4: Interrupt on dataRx_ready ---");
			// CONTRL: control[1] = dataRx_ready enable (status={dataRx_ready, is_spi_busy})
			AHBwrite(WORD, CONTRL, 8'd2);	// enable dataRx_ready IRQ only
			AHBidle;
			$fdisplay(log_fd, "%0t\tCONTRL <= 2  control=%b  spi_IRQ=%b", $time, dut.control, spi_IRQ);
			AHBwrite(WORD, FRAME, 16'd8);
			AHBidle;
			AHBwrite(WORD, CS, 8'd1);
			AHBidle;
			AHBwrite(WORD, TXDATA, 8'hA5);
			AHBidle;
			AHBwrite(WORD, ENSPI, 8'd1);
			AHBidle;
			$fdisplay(log_fd, "%0t\tENSPI=1  waiting for IRQ...", $time);
			// Wait for interrupt (should fire when dataRx_ready=1 at COMPLETE)
			wait (spi_IRQ == 1'b1);
			$fdisplay(log_fd, "%0t\tIRQ fired!  state=%0d  dataRx_ready=%b  dataRx=0x%h",
				$time, dut.spi2.currentState, dut.spi2.dataRx_ready, dut.spi2.dataRx);
			#20;
			AHBread(WORD, RXDATA, 16'h00A5);
			AHBidle;
			$fdisplay(log_fd, "%0t\tRXDATA=0x%h (expect 0x00A5)", $time, HRDATA);
			AHBwrite(WORD, CS, 8'd0);
			AHBidle;

			// =========== Test 5: TXDATA register readback ===========
			$fdisplay(log_fd, "\n--- Test 5: TXDATA register readback ---");
			AHBwrite(WORD, TXDATA, 8'h3C);
			AHBidle;
			AHBread(WORD, TXDATA, 8'h3C);
			AHBidle;
			$fdisplay(log_fd, "%0t\tTXDATA readback: HRDATA=0x%h  stored_HWDATA=0x%h (expect 0x3C)",
				$time, HRDATA, dut.stored_HWDATA);

			// =========== Summary ===========
			$fdisplay(log_fd, "\n===== Simulation Complete =====");
			$fdisplay(log_fd, "Error count: %0d", errCount);
			if (errCount == 0)
				$fdisplay(log_fd, "ALL TESTS PASSED");
			else
				$fdisplay(log_fd, "SOME TESTS FAILED — see error signal in waveform");
			$fclose(log_fd);

			#5000;
			$stop;
		end


// =========== AHB bus tasks - crude models of bus activity =========================
// To use these tasks, include everything below this line, until the next ===== line
// Read and Write tasks do not restore the bus to idle, as another transaction might follow.
// Use AHBidle task immediately after read or write if no transaction follows immediately.

	reg [31:0] nextWdata = 32'h0;		// delayed data for write transactions
	reg [31:0] expectRdata = 32'h0;		// expected read data for read transactions
	reg [31:0] rExpectRead;				// store expected read data
	reg [4:0]  rReadType;               // store size and position of read data 
	reg checkRead;						// remember that read is in progress
	reg [31:0] readCapture = 32'h0;     // to capture read data on clock edge
	reg transState;						// state of our transaction - 1 if in data phase
	reg error = 1'b0;  // read error signal - asserted for one cycle AFTER read completes
	integer errCount = 0;				// error counter
    
// Task to simulate a write transaction on AHB Lite
	task AHBwrite ( 
			input [2:0] size,	// transaction width - BYTE, HALF or WORD
			input [31:0] addr,	// address
			input [31:0] data );	// data to be written, right-justified
		begin
			wait (HREADY == 1'b1);	// wait for ready signal - previous transaction completing
			@ (posedge HCLK);	// align with clock
			#1 HSIZE = size;	// set up signals for address phase, just after clock edge
			HTRANS = NONSEQ;	// transaction type non-sequential
			HWRITE = 1'b1;		// write transaction
			HADDR = addr;		// put address on bus
			HSELx = 1'b1;		// select this slave
			#1;	// a little later, store data for use in the data phase
			// write data must be aligned according to size and LSBs of address
			case ({size, addr[1:0]})
			  5'b000_00: 	nextWdata = data & 8'hff;  // byte write LSB
			  5'b000_01: 	nextWdata = (data & 8'hff) << 8;  // byte write next byte
			  5'b000_10: 	nextWdata = (data & 8'hff) << 16;  // byte write next byte
			  5'b000_11: 	nextWdata = (data & 8'hff) << 24;  // byte write MSB
			  5'b001_00: 	nextWdata = data & 16'hffff;  // half word write LSH
			  5'b001_10: 	nextWdata = (data & 16'hffff) << 16;  // half word write MSH
			  5'b010_00,
			  5'b010_01,
			  5'b010_10,
			  5'b010_11: 	nextWdata = data;  // word write (all alignments)
			  default:      nextWdata = 32'hdeadbeef;    // anything else is invalid
			endcase
			HWDATA = nextWdata;	// drive HWDATA immediately so DUT sees it at next posedge
		end
	endtask

// Task to simulate a read transaction on AHB Lite
	task AHBread (
			input [2:0] size,	// transaction width - BYTE, HALF or WORD
			input [31:0] addr,	// address
			input [31:0] data );	// expected data from slave
		begin  
			wait (HREADY == 1'b1);	// wait for ready signal - previous transaction completing
			@ (posedge HCLK);	// align with clock
			#1 HSIZE = size;	// set up signals for address phase, just after clock edge
			HTRANS = NONSEQ;	// transaction type non-sequential
			HWRITE = 1'b0;		// read transaction
			HADDR = addr;		// put address on bus
			HSELx = 1'b1;		// select this slave
			#1 expectRdata = data;	// a little later, store expected data for checking in the data phase
		end
	endtask

// Task to put bus in idle state after read or write transaction
	task AHBidle;
		begin  
			wait (HREADY == 1'b1); // wait for ready signal - previous transaction completing
			@ (posedge HCLK);	// then wait for clock edge
			#1 HTRANS = IDLE;	// set transaction type to idle
			HSELx = 1'b0;		// deselect the slave
		end
	endtask

// Control the HWDATA signal during the data phase
	always @ (posedge HCLK)
		if (~HRESETn) HWDATA <= 32'b0;
		else if (HSELx && HWRITE && HTRANS && HREADY) // our write transaction is moving to data phase
			#1 HWDATA <= nextWdata;	// change HWDATA shortly after the clock edge
		else if (HREADY)	// some other transaction in progress
			#1 HWDATA <= {HADDR[31:24], HADDR[11:0], 12'hbad}; // put rubbish on HWDATA

// Registers to hold expected read data during data phase, data size and position
// and a flag to indicate that read is in progress
	always @ (posedge HCLK)
		if (~HRESETn)
			begin
				rExpectRead <= 32'b0;
				rReadType <= 5'b0;
				checkRead <= 1'b0;
			end
		else if (HSELx && ~HWRITE && HTRANS && HREADY)  // our read transaction moving to data phase
			begin
			    // first update expected read register with expected data
				if (HSIZE == 3'b0) rExpectRead <= expectRdata & 8'hff;  // byte read
				else if (HSIZE == 3'b1) rExpectRead <= expectRdata & 16'hffff;  // half word read
				else rExpectRead <= expectRdata;	// word read (or larger, not supported)
				
				rReadType <= {HSIZE, HADDR[1:0]};  // also store size and address bits
				checkRead <= 1'b1;	// and set flag to get read data checked on next clock edge
			end
		else if (HREADY)	// some other transaction moving to data phase
				checkRead <= 1'b0;			// clear flag - no check needed

// Check the read data as the read transaction completes
// Error signal will be asserted for one cycle AFTER problem detected
	always @ (posedge HCLK)
		if (~HRESETn) error <= 1'b0;
		else if (checkRead & HREADY)	// our read transaction is completing on this clock edge
		  begin
		    case (rReadType)  // capture the appropriate data from the bus
			  5'b000_00: 	 readCapture = HRDATA & 8'hff;  // byte read LSB
              5'b000_01:     readCapture = (HRDATA >> 8) & 8'hff;  // byte read next byte
              5'b000_10:     readCapture = (HRDATA >> 16) & 8'hff;  // byte read next byte
              5'b000_11:     readCapture = (HRDATA >> 24) & 8'hff;  // byte read MSB
              5'b001_00:     readCapture = HRDATA & 16'hffff;       // half word read LSH
              5'b001_10:     readCapture = (HRDATA >> 16) & 16'hffff; // half word read MSH
              default:       readCapture = HRDATA;  // word read (anything else is invalid)
            endcase
            
            // compare captured data with expected read data
			if (readCapture != rExpectRead)	// the captured data is not as expected
				begin
					error <= 1'b1;		// so flag this as an error
					errCount = errCount + 1;	// and increment the error counter
				end
			else error <= 1'b0;			// otherwise our read transaction is OK
		  end  // end checking our read transaction
		  
		else		// this is some other transaction 
			error <= 1'b0;	// so no error
			
// Control the HREADY signal during the data phase
	always @ (posedge HCLK)
		if (~HRESETn) transState <= 1'b0;	// after reset, this is not the data phase of our transaction
		else if (HSELx && HTRANS && HREADY) // transaction with this slave is moving to data phase
			#1 transState <= 1'b1;			// so this slave controls HREADY
		else if (HREADY)					// idle, or some other transaction is moving to data phase
			#1 transState <= 1'b0;			// some other slave controls HREADY
			
	assign HREADY = transState ? HREADYOUT : 1'b1;     // other slave is always ready

//============================= END of AHB bus tasks =========================================



endmodule
