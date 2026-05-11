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
//   tx_begin = 1'b1; // Set high to begin transmission
//   while(is_spi_busy); // wait for her to get off the phone
//   // Slave will send shit so wont bother saving
//   
//   // Send adress
//   dataTx = 0x0E; // Send XDATA_L register adress
//   tx_begin = 1'b1; // Set high to begin transmission
//   while(is_spi_busy); // wait for her to get off the phone
//   // Slave will send more shit 
//
//   // Read XDATA_L (Master's turn to send waffle)
//   dataTx = 0x00; // shite
//   tx_begin = 1'b1; // Set high to begin transmission
//   while(is_spi_busy);
//   x_accel = dataRx; // low byte 
//  
//   // If i read the data sheet right, which is probubly isn't Likely,
//   //   i think you can send junk again and it sends the High byte for the data after the Low
//   
//   // Read XDATA_H 
//   dataTx = 0x00; // shiterst
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
//    I Removed this ting i talk about below, so you just set tx_begin = 1 to run, but im thinking i you use the wait command in software to wait till 
//       you get a resonse, then set tx_begin = 0 after wait to stop it running again im nt sure if youd miss it and it'd have already statrted transmitting agian?
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
      
      // ========== Software Control ==========
       // To control the SPI master module software will be used to control registers
      input [7:0] dataTx; // byte to transmit
      input [1:0] cs_sel; // slave select (in 1-hot code for protection): 2'b00 = no selection, 2'b01 = accelerometer, 2'b10 = display 
      input reset_spi, // syncrinus spi rest 
      input tx_begin; // put high when want to start tx
      input [3:0] clkDelay; // sclk = 50MHZ/(clkDelay + 1) 



      // Output 
      output mosi, // Commands to slave
      output cs_bar_accel, // accelerometer slave select (active low)
      output cs_bar_disp, // Display slave select (active low)
      output reg sclk // Serial clock
    );
	  

    // ==== Status Registers =====
    // Software can read to see whats happening
    reg is_spi_busy = 1'b0; // sending if 1 
    reg [7:0] dataRx = 8'b0; // byte that was recived

    // === Other registers === 
    reg [3:0] countClk = 4'b0; // counts the clock edges
    //reg [4:0] delayEdges; // Number of edge to delay clk by. Set on register vale software sider (Rember value starts at 0)
    reg [7:0] shiftReg = 8'b0;
    reg [3:0] countBit = 4'b0; // keeps track of current bit
    //reg sclkVal = 1'b0; // sclk value (as accelerometer data sheet says CPHA = CPOL = 0)
    reg sclk_prevVal = 1'b0; // the previus sclk value
    reg has_tx_started = 1'b0;// to make sure spi communication doesnt start before inital set up is complete
    reg tx_begin_prev = 1'b0;
    reg [1:0] safe_cs_sel; // cs_sel after safty checks
    reg update_mosi = 1'b0; // output of state machine, decides when to update mosi
    reg read_miso = 1'b0; // output of state machine, decides when to read miso
    reg nextMosi = 1'b0;
    reg [7:0] nextShiftReg = 7'b0;
    reg prep_shiftReg = 1'b0;
    reg [3:0] nextCountBit = 3'b0;
    wire is_cs_sel_1hot;
    wire cs_sel_H, cs_sel_L;
    wire sclk_rising, sclk_falling;
    reg nextSclk;
    reg nexCountClk;
    



    // ======= States =====
    localparam [1:0] IDLE = 2'b00, // Inital state
                     PREP = 2'b01, // Preperation before TX
                     TX = 2'b10, // Master is communicating with slave
                     //COMPLETE = 2'b11; // communication complete

    reg [1:0] currentState = IDLE;
    reg [1:0] nextState;


 
	  // Nexys4 data sheet recomends sclk between 1MHZ and 5MHz for accelerometer,
    // seven-segment has max sclk of 10MHz
    // Will delay clk to give sclk of 5MHz 
    
    // ========== Clock delayer =====
    // sclk register
    always @ (posedge clk)
         sclk <= nextSclk;
    
    // input MUX to sclk register 
    always @ (clkDelay, countClk, sclk)
        if (clkDelay == countClk)
          nextSclk = ~sclk;
        else 
          nextSclk = sclk;


   // countClk register, increase 1 each clock, register reset is triggered when clkDelay == countClk
   always @ (posedge clk)
        if (clkDelay == countClk) countClk <= 4'b0;// syncrinus reset 
        else countClk <= countClk + 4'b1;



/*
 *  SHITE
    always @ (posedge clk)
    begin 
      if (countClk == clkDelay)
      begin
        countClk <= 4'b0;
        //sclk_prevVal <= sclkVal;
        sclkVal <= ~sclkVal;
      end
      else 
        countClk <= countClk + 1'b1;
    end 

    assign sclk = sclkVal;

*/
    // ========= sclk edge ditector=======
    always @ (posedge clk) 
      sclk_prevVal <= sclk;

    //wire sclk_rising = (sclkVal == 1'b1 && sclk_prevVal == 1'b0);
    //wire sclk_falling =  (sclkVal ==1'b0 && sclk_prevVal == 1'b1);
    
    assign sclk_rising = sclk & ~sclk_prevVal; // if high then pos edge detected
    assign sclk_falling = ~sclk & sclk_prevVal; // if high neg edge detected 

    // ======= slave select ========    
    // The 2 bit cs_sel is first broken for safty check and use
    assign cs_sel_H = cs_sel[0];
    assign cs_sel_L = cs_sel[1];
    
    // To be valid cs_sel must be in one hot code, XOR gate is used to make sure 
    assign is_cs_sel_1hot = cs_sel_H ^ cs_sel_L; 
    
    // To make sure only one sleve is ever selected a multiplexer 
    // The MUX slect is controlsed by is_cs_sel_valid and currentState
    // Current state must be TX or TX_coplete (this stops slave bing actice when master is IDLE)
     always @ (cs_sel, is_cs_sel_1hot, currentState)
      case({is_cs_sel_1hot, currentState})
        3'b101:   safe_cs_sel = cs_sel;
        3'b110:   safe_cs_sel = cs_sel;
        default:  safe_cs_sel = 2'b0;
      endcase

      // Slave select one hot code: 2'b01 = accelerometer, 2'b10 = display [2'b00 = no selection]
      // After safty checks cs_sel is broken up into seperate outputs, these are hardware wired to their respective slave divices.
      // The slaves have active low CS so this is taken account of here
      //assign cs_bar_accel = ~cs_sel[1]; 
      //assign cs_bar_disp = ~cs_sel[0];
      
      // Registers for slave selects 
      always @ (posedge clk)
        cs_bar_accel <= ~safe_cs_sel[1];

      always @ (posedge clk)
        cs_bar_disp <= ~safe_cs_sel[0];


    // ======= tx_begin fix for software control ====
    //
    // REMOVED: I think youd loose a clock with this if you tried to go for two bytes in a row
    //
    // needed to prevent software control failing to end tx on time causing infinit loop
    //always @ (posedge clk) tx_begin_prev <= tx_begin;
     // tx_starter will only allow another transmission if tx_begin has been
   // disabled then enabled again, to prevent getting stuck in an infinite loop
    //wire tx_starter = (tx_begin == 1'b1 && tx_begin_prev == 1'b0);
    //wire tx_starter = ~tx_begin_prev & tx_begin;



    /* ====================================================================
    *                 ALLL SHIT 
    *
    *  
    // === MOSI ====
    //assign mosi = shiftReg[7];

    // ==== SPI Communication State Machine ====
    // This is done as a Maealy machine because the TX state outputs as depend on the inputs
    // Inputs: tx_starter, dataTx, sclk_rising, sclk_falling, miso
    // Outputs: is_spi_busy, countBit, shiftReg, dataRx
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
              currentState <= COMPLETE;
            end
          end

      COMPLETE: begin
                    is_spi_busy <= 1'b0;
                    currentState <= IDLE;
                   end

    endcase 
    end

====================================================================== */

 

    // ======= Proper state machine =======================================
    
    // === State register
    always @ (posedge clk) 
    begin
      if (reset_spi) // syncrinus reset 
        currentState <= IDLE;
      else 
        currentState <= nextState;
    end


    // === Next state logic 
    always @ (currentState, tx_begin, countBit)
      begin
        nextState = currentState; // default is no change
        case (currentState)
           IDLE:          if (tx_begin) nextState = PREP;
                          else nextState = IDLE;

           PREP:          nextState = TX;
          
           // Tx state loops untill all bits are recived.
           TX:            if (countBit == 4'b1000) nextState = IDLE; 
                          else nextState = TX;;

           default: nextState = IDLE; // safty
        endcase
      end


    // ==== State output logic
    always @ (currentState, sclk_rising, sclk_falling) // mealy meachine so inputs are included 
      case (currentState)
        IDLE:  begin
                  is_spi_busy = 1'b0;
                  prep_shiftReg = 1'b0;
                  update_mosi = 1'b0;
                  read_miso = 1'b0;
              end

        PREP:  begin
                  // inital set up before communication
                  is_spi_busy = 1'b1; // so software side knows spi is currently communicating
                  prep_shiftReg = 1'b1; // signals to place data for Rx to slave in shiftReg
                  update_mosi = 1'b0;
                  read_miso = 1'b0;
               end



        TX:    begin
                   // Once setup is complete communicating can begin
                   // Based on accelerometer spi: 
                   //     CPOL = 0 (sclk idle state = 0, low on first edge), 
                   //     CPHA = 0 (MOSI and MISO change on odd clock edge, sample on even edges) 
                   //         As first sclk edge is 0:
                   //               Odd clock edges happen on risng edges, 
                   //               Even clock edges happen on falling
                   //
                   // mosi only changes on rising edges
                   if (sclk_rising) 
                       begin
                         is_spi_busy = 1'b1; // so software side knows spi is currently communicating
                         prep_shiftReg = 1'b0;
                         update_mosi = 1'b1;
                         read_miso = 1'b0;
                       end 

                   // Sampling miso on falling edges
                   if (sclk_falling)
                       begin
                           // When the master samples the slave output, the slave output is shifted into the lowest bit position of shiftReg.
                           //   The shift causes the highst bit to be replaced with the second highest, this means the next bit for the master 
                           //   to send is ready (mosi only updates on even clock edges).
                           is_spi_busy = 1'b1; // so software side knows spi is currently communicating
                           prep_shiftReg = 1'b0;
                         update_mosi = 1'b0;
                           read_miso = 1'b1;
                       end
              end
        endcase
/*
         COMPLETE:    begin
                           dataRx = shiftReg;
                           has_tx_started = 1'b0;
                       end
*/

// ====== SPI Communication Logic =========
// MOSI register
always @ (posedge clk)
    mosi <= nextMosi;
 
// MUX input to mosi register
always @ (update_mosi, shiftReg, mosi)
    begin
         if (update_mosi) nextMosi = shiftReg[7];
         else nextMosi = mosi;
    end

// shiftReg register 
always @ (posedge clk)
  shiftReg <= nextShiftReg;

// MUX to change shiftReg register input 
always @ (prep_shiftReg, read_miso, dataTx, shiftReg, miso)
    case({prep_shiftReg, read_miso})
        2'b10:    nextShiftReg = dataTx;
        2'b01:    nextShiftReg = {shiftReg[6:0], miso};
        default: nextShiftReg = shiftReg;
    endcase 

// countBit register
always @ (posedge clk)
  countBit <= nextCountBit;

// MUX to increase countBit 
always @ (read_miso, countBit)
    begin
         if (read_miso) nextCountBit = countBit + 1'b1;
         else nextCountBit = countBit;
    end

        


    endmodule




            


