//TODO: SPI for accel and disp 
// Accel is 4-wire SPI (but can also has two interup signals that coulb be used)
// This SPI in  terface will connect to AHB-Lite bus and will handel a SPI signals
// Will add registers that can access with from software to control the
// interface and to transfer bytes 
// Normal to use hardware to transfer bytes to and from slave
// The sequence bytes for a perticular slave will be handled in software ????
// --- that keeps hardware simple and allows multiple slaves 
// Four SPI sgnals for accel already in top module (they have been commented
// out though)
//
// Using this thing that has taken my life:
// - All of these registers can be read by the software side.
// - This SPI module is controlled with software.... i know disgusting
//
//    - The registers in Software Control control the spi:
//        clkDelay - base clock is 50MHz, too fast for accelerometer and
//                    display SPI's. This registers value sets the sclk.
//                    sclk = 50MHZ/(clkDelay + 1). 
//                    I think we should set it to 5MHz sclk
//        dataTx - Is the byte you want to send from master to slave using MISO
//                 Example: accelerometer has these Commands:
//                          0x0A: Write register 
//                          0x0B: read register 
//                          0x0D: read FIFO 
//        tx_begin - set to 1 to begin transmission, note to stop the
//                    infinite loop. After TX is complete it wont sent again
//                    untill its been cycled off and on again to meed a safty
//                    condition.
//
//       cs_sel - slave select:
//                     2'b00 = no selection, 
//                     2'b01 = accelerometer, 
//                     2'b10 = display 
//
//
//     - The registers in Status Registers tell you whats up:
//            is_spi_busy - High if she's on the phone. 
//
//            dataRx - This is the byte that was sent MISO is a bit at a time
//                      that shifts into shiftReg once finished dataRx is
//                      updated, TX is finished and is_spi_busy goes low. 
//                      Now .... there is a thing is that the accelerometer
//                      does 12-bit output resolution or 8-bit lower
//                      resolution, where its litrally data_L = [7:0], data_H
//                      = [11:8] and i just take the lower res 7:0 because
//                      i dont know if we needed it and im lazy.
//                  
//  The software can read all internal modual registers (can't read wires)
//                      
//  So the plan is, this guy is hardware wired up to the slaves, we control 
//  this guy with software, she calls up the slaves at out requestm,then we use 
//  software to wiretap their conversation and get slave data 
//
//
// 
//
//   ================
//   Example Software Code Usage (written in Sam-code, who knows if it will work)
//   ==============================
//
//   // Before we begin, if you havent read the module. how it basically works
//   //   is it first this module makes a slower clock (sclk) from the main clock (clk).
//   //
//   // To transmit to the slave, cs_sel is used to select a slave,
//   //   the masters 8-bit Tx message is placed in shiftReg (also 8-bit), 
//   //   once ready set up and ready to send tx_begin is set low then high.
//   //
//   // During a transmission, is_spi_busy register is set high.
//   //   MOSI (masters message) is assigned to always be shiftReg's bit 7
//   //   shiftReg[7], the slave then reads this each sclk.
//   //   On each risng edge, the slave response (MISO) is shifted into bit 0
//   //   of shiftReg, eliminating the 7th bit. Once the 8-bits have been recived from
//   //   slave they are placed in dataRx, is_spi_busy is set low again and
//   /    SPI idles.
//   //  
//   //   Because of how mosi and miso are on opisit ends of shiftReg, the
//   //   response from thr slave will always be 8 clock cycles (or one tx session)
//   //   behind. - I am ashamed to addmit this took me longer to realise than
//   //   i am willing to addmit. 
//   //
//   //   Like for example you want to read a register:
//   //   Step 1.)  Master sends the read command 0x0B, Slave send shite.
//   //   Step 2.)  Master sends the address to read, Slave send shit.
//   //   --- Because slave is behind by 8 cycles Master needs to send shite ---
//   //   Step 3.)  Master sends shite, Slave send 8-bits from register.
//
//
//
//   === Setup ====
//    uint16 x_accel; // accelerometer X-axis data
//
//   clkDelay = 4'b1001; // SCLK = 50MHz / (9+1) = 5MHz 
//   cs_sel = 1'b0; // no slave selected 
//
//   === Read accelerometer register ===
//   cs_sel = 2'b01; // select accelerometer
//
//   // Send command 
//   dataTx = 0x0B; // Send the accelerometer read register command
//   tx_begin = 1'b0; // To meet a requird tx condition always set tx_begin low frst
//   tx_begin = 1'b1; // Set high to begin transmission
//   while(is_spi_busy); // wait for her to get off the phone
//   // Slave will send shit so wont bother saving
//   
//   // Send adress
//   dataTx = 0x0E; // Send XDATA_L register adress
//   tx_begin = 1'b0; // To meet a requird tx condition always set tx_begin low frst
//   tx_begin = 1'b1; // Set high to begin transmission
//   while(is_spi_busy); // wait for her to get off the phone
//   // Slave will send more shit 
//
//   // Read XDATA_L (Master's turn to send waffle)
//   dataTx = 0x00; // shite
//   tx_begin = 1'b0; // To meet a requird tx condition always set tx_begin low frst
//   tx_begin = 1'b1; // Set high to begin transmission
//   while(is_spi_busy);
//   x_accel = dataRx; // low byte 
//  
//   // If i read the data sheet right, which is probubly isn't Likely,
//   //   i think you can send junk again and it sends the High byte for the data after the Low
//   
//   // Read XDATA_H 
//   dataTx = 0x00; // shite
//   tx_begin = 1'b0; // To meet a requird tx condition always set tx_begin low frst
//   tx_begin = 1'b1; // Set high to begin transmission
//   while(is_spi_busy);
//   x_accel |= (dataRx << 8); // H and L combined, results in 16-bit (or half-word i belive is how they say it) with 12 bits i care about
//    
//    // And now we have the 12-bit x-axis data on the software side (once we
//    //  figure out the spi master module registers hardware adresses OFC)
//    //
//    // The plan then i gues would be to feed that data into some 7-segment
//    //    converter lookup table thing and use SPI to tx it ot the display
//    // 
//    // I have yet to refresh myself on the 7-segments, but im sure its
//    //   standardised... it's spi ofc :)
//
//
//
//
//
//   // Why do you have to do tx_begin low high thing I hear you complaining? well... 
//
//   //  ``The following condition had to be added for unexcapeable 
//   //    infinite loop reasons.
//   //    To begin Tx, the following must be true:        //
//   //    tx_starter = (tx_begin == 1'b1 && tx_begin_prev == 1'b0)  //
//   //              [tx_starter starts the transmission]           //
//   //    [Every positve clock edge this is done: tx_begin_prev <= tx_begin;]
//   
//    
//      
//
//
//
//
//
//
//

module AHBspi(
      // Inputs
      input clk, // System clock
      input miso, // Data from slave
      // Output 
      output mosi, // Commands to slave
      output cs_bar_accel, // accelerometer slave select (active low)
      output cs_bar_disp, // Display slave select (active low)
      output sclk // Serial clock
    );
	  
    // ========== Software Control ==========
    // To control the SPI master module software will be used to control registers
    reg [3:0] clkDelay; // sclk = 50MHZ/(clkDelay + 1) 
    reg [7:0] dataTx; // byte to transmit
    reg tx_begin; // put high when want to start tx
    reg [1:0] cs_sel; // 2'b00 = no selection, 2'b01 = accelerometer, 2'b10 = display 

    // ==== Status Registers =====
    // Software can read to see whats happening
    reg is_spi_busy = 1'b0; // sending if 1 
    reg [7:0] dataRx = 8'b0; // byte that was recived

    // === Other registers === 
    reg [3:0] countClk = 4'b0; // counts the clock edges
    //reg [4:0] delayEdges; // Number of edge to delay clk by. Set on register vale software sider (Rember value starts at 0)
    reg [7:0] shiftReg = 8'b0;
    reg [3:0] countBit = 4'b0; // keeps track of current bit
    reg sclkVal = 1'b0; // sclk value
    reg sclk_prevVal = 1'b0; // the previus sclk value
    reg has_tx_started =1'b0;
    reg tx_begin_prev = 1'b0;



    // ======= States =====
    localparam IDLE = 2'b00;
    localparam TX = 2'b01;
    localparam TX_COMPLETE = 2'b10;

    reg [1:0] currentState = IDLE;


 
	  // Nexys4 data sheet recomends sclk between 1MHZ and 5MHz for accelerometer,
    // seven-segment has max sclk of 10MHz
    // Will delay clk to give sclk of 5MHz 
    
    // ========== Clock delayer =====
    always @ (posedge clk)
    begin 
      if (countClk == clkDelay)
      begin
        countClk <= 5'b0;
        sclkVal <= ~sclkVal;
      end
      else 
        countClk <= countClk + 1'b1;
    end 

    assign sclk = sclkVal;


    // ========= sclk edge ditector=======
    always @ (posedge clk) sclk_prevVal <= sclkVal;

    wire sclk_rising = (sclkVal == 1'b1 && sclk_prevVal == 1'b0);
    wire sclk_falling =  (sclkVal ==1'b0 && sclk_prevVal == 1'b1);


    // ======= Chip select ========
    // TODO: Decide: This is to ignore when in IDLE but this might be bad practice, im notsure?
    assign cs_bar_accel = ~(cs_sel == 2'b01 && (currentState == TX || currentState == TX_COMPLETE));
    assign cs_bar_disp = ~(cs_sel == 2'b10 && (currentState == TX || currentState == TX_COMPLETE));

    // ======= tx_begin fix for software control ====
    // needed to prevent software control failing to end tx on time causing infinit loop
    always @ (posedge clk) tx_begin_prev <= tx_begin;
     // tx_starter will only allow another transmission if tx_begin has been
   // disabled then enabled again, to prevent getting stuck in an infinite loop
    wire tx_starter = (tx_begin == 1'b1 && tx_begin_prev == 1'b0);
    


    // === MOSI ====
    assign mosi = shiftReg[7];

    // ==== Main SPI State Machine ====
    always @ (posedge clk) 
    begin
    case (currentState)
      IDLE: begin
              is_spi_busy <= 1'b0;
              countBit <= 4'b0;
              has_tx_started <= 1'b0;

              if (tx_starter) 
              begin
                is_spi_busy <= 1'b1;
                shiftReg <= dataTx;
                currentState <= TX;
              end
            end
            

      TX: begin
            if (sclk_rising && has_tx_started == 1'b0) has_tx_started <= 1'b1; // start after falling edge

            if (sclk_falling && has_tx_started) 
            begin
              shiftReg <= {shiftReg[6:0], miso}; // if tx has started, shift slave output in register
              countBit <= countBit + 1'b1; // increase bit count on each falling edge if tx has started
            end 

            if (countBit == 4'b1000 && sclk_rising)
            begin
              dataRx <= shiftReg;
              currentState <= TX_COMPLETE;
            end
          end
      TX_COMPLETE: begin
                    is_spi_busy <= 1'b0;
                    currentState <= IDLE;
                   end

    endcase 
    end
    endmodule




            


