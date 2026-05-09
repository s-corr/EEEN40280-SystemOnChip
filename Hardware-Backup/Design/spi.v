`timescale 1ns / 1ns
////////////////////////////////////////////////////////////////////////////////
// Create Date:   April 2026
// Design Name: 	Cortex-M0 DesignStart system
// Module Name:   AHBspi
// Description: 	Provides SPI master interface on AHB bus.
//					Transmit and receive paths have 16-byte FIFO buffers.
//		Address 0 - receive data, 8 bits, from FIFO, read only
//		Address 4 - transmit data, 8-bits, to FIFO (read gives FIFO output)
//		Address 8 - status, read only: 	bit 0 = tx FIFO full
//										bit 1 = tx FIFO empty
//										bit 2 = rx FIFO full
//										bit 3 = rx not empty - data available
//		Address C - control - bit 0 = SPI enable, bits[7:4] = clock divider
//					Clock frequency = HCLK / (2 * (divider + 1))
//					divider = 0 gives SCLK = HCLK / 2 (max speed)
//					divider = 15 gives SCLK = HCLK / 32 (slowest)
//
// Revision: 
// Revision 0.01 - File Created
//
////////////////////////////////////////////////////////////////////////////////
module AHBspi(
			// Bus signals
			input  HCLK,			// bus clock
			input  HRESETn,			// bus reset, active low
			input  HSEL,			// selects this slave
			input  HREADY,			// indicates previous transaction completing
			input  [31:0] HADDR,	// address
			input  [1:0] HTRANS,	// transaction type (only bit 1 used)
			input  HWRITE,			// write transaction
			input  [31:0] HWDATA,	// write data
			output [31:0] HRDATA,	// read data from slave
			output HREADYOUT,		// ready output from slave
			output HRESP,			// response output from slave
			// SPI signals
			output SSel_n,			// slave select, active low
			output SCLK,			// serial clock
			output MOSI,			// master out slave in
			input  MISO,			// master in slave out
			output spi_IRQ			// interrupt request
     );
	
	reg [1:0] rHADDR;
	reg rWrite, rRead;

	reg [7:0]	readData;
	wire [7:0] rx_fifo_out, rx_fifo_in, tx_fifo_out;
	wire rx_fifo_empty, rx_fifo_full, tx_fifo_empty, tx_fifo_full;
	wire tx_fifo_wr = rWrite & (rHADDR == 2'h1);
	wire rx_fifo_rd = rRead & (rHADDR == 2'h0);
	wire tx_ready;
	wire tx_busy;
	wire tx_start;
	wire rx_new;
	wire [7:0] rx_data;

	reg [7:0] control;
	wire spi_en;
	wire [3:0] clk_div;
	
	assign spi_en = control[0];
	assign clk_div = control[7:4];

	wire [3:0] status = {~rx_fifo_empty, rx_fifo_full, tx_fifo_empty, tx_fifo_full};
	
	assign spi_IRQ = ~rx_fifo_empty;
	
	always @(posedge HCLK)
		if(!HRESETn)
			begin
				rHADDR <= 2'b0;
				rWrite <= 1'b0;
				rRead  <= 1'b0;
			end
		else if(HREADY)
		 begin
			rHADDR <= HADDR[3:2];
			rWrite <= HSEL & HWRITE & HTRANS[1];	     
			rRead <= HSEL & ~HWRITE & HTRANS[1];
		 end

	always @(posedge HCLK)
		if (!HRESETn) control <= 8'b0;
		else if (rWrite && (rHADDR == 2'h3)) control <= HWDATA[7:0];
		
	always @(rx_fifo_out, tx_fifo_out, status, control, rHADDR)
		case (rHADDR)
			2'h0:		readData = rx_fifo_out;
			2'h1:		readData = tx_fifo_out;
			2'h2:		readData = {4'b0, status};	    
			2'h3:		readData = {4'b0, control[3:0]};
		endcase
		
	assign HRDATA = {24'b0, readData};

	assign HREADYOUT = 1'b1;
	assign HRESP = 1'b0;
	
	  FIFO  #(.DWIDTH(8), .AWIDTH(4))
		uFIFO_TX (
	    .clk(HCLK),
	    .resetn(HRESETn),
	    .rd(tx_ready),
	    .wr(tx_fifo_wr),
	    .w_data(HWDATA[7:0]),
	    .empty(tx_fifo_empty),
	    .full(tx_fifo_full),
	    .r_data(tx_fifo_out)
	  );
	  
	  FIFO  #(.DWIDTH(8), .AWIDTH(4))
		uFIFO_RX (
	    .clk(HCLK),
	    .resetn(HRESETn),
	    .rd(rx_fifo_rd & ~rx_fifo_empty),
	    .wr(rx_new),
	    .w_data(rx_fifo_in),
	    .empty(rx_fifo_empty),
	    .full(rx_fifo_full),
	    .r_data(rx_fifo_out)
	  );

   spi_master #(.N(8)) spi_inst (
        .clk        (HCLK),
        .rst        (~HRESETn),
        .en         (spi_en),
        .divider    (clk_div),
		.tx_data	(tx_fifo_out),
		.tx_ready	(tx_ready),
		.tx_start	(tx_start),
		.rx_data	(rx_fifo_in),
		.rx_new		(rx_new),
		.SS_n		(SSel_n),
		.SCLK		(SCLK),
		.MOSI		(MOSI),
        .MISO       (MISO)
	   );
	   
	assign tx_start = ~tx_fifo_empty & ~tx_busy & spi_en;
	
	always @(posedge HCLK)
		if (!HRESETn) tx_busy <= 1'b0;
		else if (tx_start) tx_busy <= 1'b1;
		else if (tx_ready) tx_busy <= 1'b0;
	   
endmodule


module spi_master #(
    parameter N = 8
)(
    input clk,
    input rst,
    input en,
    input [3:0] divider,
    
    input [N-1:0] tx_data,
    output reg tx_ready,
    input tx_start,
    
    output reg [N-1:0] rx_data,
    output reg rx_new,
    
    output reg SS_n,
    output reg SCLK,
    output reg MOSI,
    input MISO
);

localparam IDLE = 2'b00,
           TRANSFER = 2'b01,
           DONE = 2'b10;

reg [1:0] state, next;
reg [4:0] div_cnt;
reg [3:0] bit_cnt;
reg [N-1:0] shift_reg;

wire [4:0] period = {divider, 1'b1};
wire full_period = div_cnt == period;

always @(posedge clk)
    if (rst || ~en) state <= IDLE;
    else state <= next;

always @(*) begin
    case (state)
        IDLE:   if (tx_start) next = TRANSFER;
                else next = IDLE;
        TRANSFER: if (bit_cnt == 4'b0 && full_period) next = DONE;
                  else next = TRANSFER;
        DONE:   next = IDLE;
        default: next = IDLE;
    endcase
end

always @(posedge clk) begin
    if (rst || ~en) begin
        div_cnt <= 5'b0;
    end else if (state == IDLE) begin
        div_cnt <= 5'b0;
    end else if (full_period) begin
        div_cnt <= 5'b0;
    end else begin
        div_cnt <= div_cnt + 5'b1;
    end
end

always @(posedge clk) begin
    if (rst || ~en) SCLK <= 1'b0;
    else if (state == IDLE) SCLK <= 1'b0;
    else if (full_period) SCLK <= ~SCLK;
end

always @(posedge clk) begin
    if (rst || ~en) bit_cnt <= 4'b0;
    else if (state == IDLE) bit_cnt <= 4'b0;
    else if (state == TRANSFER && full_period) bit_cnt <= bit_cnt + 4'd1;
end

always @(posedge clk) begin
    if (rst || ~en) begin
        shift_reg <= {N{1'b0}};
        SS_n <= 1'b1;
        tx_ready <= 1'b1;
        rx_new <= 1'b0;
        MOSI <= 1'b0;
    end else if (state == IDLE) begin
        if (tx_start) begin
            shift_reg <= tx_data;
            SS_n <= 1'b0;
            tx_ready <= 1'b0;
        end else begin
            tx_ready <= 1'b1;
        end
        rx_new <= 1'b0;
    end else if (state == TRANSFER) begin
        if (full_period) begin
            shift_reg <= {shift_reg[N-2:0], MISO};
            MOSI <= shift_reg[N-1];
        end
    end else if (state == DONE) begin
        rx_data <= shift_reg;
        rx_new <= 1'b1;
        SS_n <= 1'b1;
    end
end

endmodule
