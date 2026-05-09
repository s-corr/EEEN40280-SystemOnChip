`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.04.2026 14:31:26
// Design Name: 
// Module Name: SPI
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module SPI(
                // Bus signals
    input  HCLK,            // bus clock
    input  HRESETn,            // bus reset, active low
    input  HSEL,            // selects this slave
    input  HREADY,            // indicates previous transaction completing
    input  [31:0] HADDR,    // address
    input  [1:0] HTRANS,    // transaction type (only bit 1 used)
    input  HWRITE,            // write transaction
    //            input  [2:0] HSIZE,        // transaction width ignored
    input  [31:0] HWDATA,    // write data
    output [31:0] HRDATA,    // read data from slave
    output HREADYOUT,        // ready output from slave
    output HRESP,            // response output from slave
    
    // STUFFF
    output MOSI,
    output SCLK,
    output CSn,
    input MISO
    );
// Registers to hold signals from address phase
    reg [1:0] rHADDR;            // only need two bits of address
    reg rWrite, rRead;    // write enable signals

    // Internal signals
    reg [7:0]    readData;        // 8-bit data from read multiplexer
    wire [7:0] rx_fifo_out, rx_fifo_in, tx_fifo_out;  // fifo data
    wire rx_fifo_empty, rx_fifo_full, tx_fifo_empty, tx_fifo_full;  // fifo output signals
    wire tx_fifo_wr = rWrite & (rHADDR == 2'h1);  // tx fifo write on write to address 0x4
    wire rx_fifo_rd = rRead & (rHADDR == 2'h0);  // rx fifo read on read to address 0x0
    wire txrdy;        // transmitter status signal
    wire txgo = ~tx_fifo_empty;    // transmitter control signal
    wire rxnew;        // receiver strobe output

     // Capture bus signals in address phase
    always @(posedge HCLK)
        if(!HRESETn)
            begin
                rHADDR <= 2'b0;
                rWrite <= 1'b0;
                rRead  <= 1'b0;
            end
        else if(HREADY)
         begin
            rHADDR <= HADDR[3:2];         // capture address bits for for use in data phase
            rWrite <= HSEL & HWRITE & HTRANS[1];    // slave selected for write transfer       
            rRead <= HSEL & ~HWRITE & HTRANS[1];    // slave selected for read transfer 
         end

    // Control register
    reg [3:0] control;    // holds interrupt enable bits
    always @(posedge HCLK)
        if (!HRESETn) control <= 4'b0;
        else if (rWrite && (rHADDR == 2'h3)) control <= HWDATA[3:0];
        
    // Status bits - can read in status register, can cause interrupts if enabled
    wire [3:0] status = {~rx_fifo_empty, rx_fifo_full, tx_fifo_empty, tx_fifo_full};
    
    // Interrupt signal - AND each status bit with enable bit, then OR all the results
    assign uart_IRQ = |(status & control);
        
    // Bus output signals
    always @(rx_fifo_out, tx_fifo_out, status, control, rHADDR)
        case (rHADDR)        // select on word address (stored from address phase)
            2'h0:        readData = rx_fifo_out;    // read from rx fifo - oldest received byte
            2'h1:        readData = tx_fifo_out;    // read of tx register gives oldest byte in queue
            2'h2:        readData = {4'b0, status};    // status register        
            2'h3:        readData = {4'b0, control};    // read back of control register
        endcase
        
    assign HRDATA = {24'b0, readData};    // extend with 0 bits for bus read

    /* The UART block does not need wait states, and does not report errors.
       The programmer should check the status bits before trying to write transmit data
       or read received data, to be sure that this will succeed.  */
    assign HREADYOUT = 1'b1;    // always ready
    assign HRESP = 1'b0;        // always OKAY
    
// ========================= FIFOs ===================================================
      //Transmitter FIFO
      FIFO  #(.DWIDTH(8), .AWIDTH(4))
        uFIFO_TX (
        .clk(HCLK),
        .resetn(HRESETn),
        .rd(txrdy & txgo),        // same signal that loads data register in transmitter
        .wr(tx_fifo_wr),
        .w_data(HWDATA[7:0]),
        .empty(tx_fifo_empty),
        .full(tx_fifo_full),
        .r_data(tx_fifo_out)
      );
      
      //Receiver FIFO
      FIFO  #(.DWIDTH(8), .AWIDTH(4))
        uFIFO_RX (
        .clk(HCLK),
        .resetn(HRESETn),
        .rd(rx_fifo_rd & ~rx_fifo_empty),
        .wr(rxnew),
        .w_data(rx_fifo_in),
        .empty(rx_fifo_empty),
        .full(rx_fifo_full),
        .r_data(rx_fifo_out)
      );

// ========================= UART ===================================================
// Simple self-contained UART, fixed 19200 bit/s, 8 data, no parity, 1 stop bit
   uart uart2 (
        .clk        (HCLK),          // 50 MHz clock
        .rst        (~HRESETn),       // asynchronous reset
        .txdin        (tx_fifo_out),
        .txgo        (txgo),
        .txrdy        (txrdy),
        .txd        (serialTx),
        .rxd        (serialRx),      // serial data in (idle at logic 1)
        .rxdout     (rx_fifo_in),        // 8-bit received data
        .rxnew      (rxnew)       // one-cycle strobe signal
       );
   
endmodule

