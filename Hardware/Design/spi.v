`timescale 1ns / 1ns


module spi(
      // Inputs
      input clk, // System clock
      input miso, // Data from slave 
      
      // ========== Software Control ==========
       // To control the SPI master module software will be used to control registers
      input [7:0] dataTx, // byte to transmit
      //input cs_sel, // slave select (Only 1 spi slave): Low = no selection, High = accelerometer
      input reset_spi, // syncrinus spi rest (active low) TODO: Add reset to all registers (currently just state machine)
      input tx_begin, // put high when want to start tx
      input [3:0] clkDelay, // sclk = 50MHZ/2*(clkDelay + 1) 
      input [5:0] frameBits, // bits needed for a completed transaction 

      // Output 
      output reg mosi, // Commands to slave
      //output reg cs_bar_accel, // accelerometer slave select (active low)
      //output reg cs_bar_disp, // Display slave select (active low)
      output reg sclk, // Serial clock
      output reg [15:0] dataRx, // two bytes recived from SPI slave (acl only has 16 bit output, so ignore the two HSBs)
      output reg dataRx_ready, // dataRx can be read when high
      output reg is_spi_busy // sending if 1 
    );
	  

    // ==== Status Registers =====
    // Software can read to see whats happening
    //reg is_spi_busy = 1'b0; // sending if 1 
    //reg [7:0] dataRx = 8'b0; // byte that was recived

    // === Other registers === 
    reg [4:0] countClk = 5'b0; // counts the clock edges
    //reg [4:0] delayEdges; // Number of edge to delay clk by. Set on register vale software sider (Rember value starts at 0)
    reg [15:0] shiftReg = 16'b0;
    reg [5:0] countBit = 6'b0; // keeps track of current bit
    //reg sclkVal = 1'b0; // sclk value (as accelerometer data sheet says CPHA = CPOL = 0)
    reg sclk_prevVal = 1'b0; // the previus sclk value
    reg has_tx_started = 1'b0;// to make sure spi communication doesnt start before inital set up is complete
    reg tx_begin_prev = 1'b0;
    //reg [1:0] safe_cs_sel; // cs_sel after safty checks
    reg update_mosi = 1'b0; // output of state machine, decides when to update mosi
    reg read_miso = 1'b0; // output of state machine, decides when to read miso
    reg nextMosi = 1'b0;
    reg [15:0] nextShiftReg = 16'b0;
    reg prep_shiftReg = 1'b0;
    reg [5:0] nextCountBit = 6'b0;
    //wire is_cs_sel_1hot;
    //wire cs_sel_H, cs_sel_L;
    wire sclk_rising, sclk_falling;
    reg nextSclk;
    reg [4:0] nextCountClk;
    



    // ======= States =====
    localparam [1:0] IDLE = 2'b00, // Inital state
                     PREP = 2'b01, // Preperation before TX
                     TX = 2'b10, // Master is communicating with slave
                     COMPLETE = 2'b11; // communication complete

    reg [1:0] currentState = IDLE;
    reg [1:0] nextState;


 
	  // Nexys4 data sheet recomends sclk between 1MHZ and 5MHz for accelerometer,
    // seven-segment has max sclk of 10MHz
    // Will delay clk to give sclk of 5MHz 
    
    // ========== Clock delayer =====
    // sclk register
    always @ (posedge clk)
         if (!reset_spi) sclk <= 1'b0;
         else sclk <= nextSclk;
    
    // input MUX to sclk register 
    always @ (clkDelay, countClk, sclk)
        if (clkDelay == countClk)
          nextSclk = ~sclk;
        else 
          nextSclk = sclk;


   // countClk register, increase 1 each clock, register reset is triggered when clkDelay == countClk
   always @ (posedge clk)
        if (!reset_spi) 
            countClk <= 5'b0;
        else 
            countClk <= nextCountClk;

    // input MUX to countClock register 
    always @ (clkDelay, countClk, sclk)
        if (clkDelay == countClk) 
             nextCountClk = 5'b0;
        else 
            nextCountClk = countClk + 5'd1;


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
      if (!reset_spi) 
        sclk_prevVal <= 1'b0;// sclk is low idle (inital clock state), so will set to opposite
      else
        sclk_prevVal <= sclk;

    //wire sclk_rising = (sclkVal == 1'b1 && sclk_prevVal == 1'b0);
    //wire sclk_falling =  (sclkVal ==1'b0 && sclk_prevVal == 1'b1);
    
    assign sclk_rising = sclk & ~sclk_prevVal; // if high then pos edge detected
    assign sclk_falling = ~sclk & sclk_prevVal; // if high neg edge detected 

/*
REMOVED: Only have one SP slave

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
        if (!reset_spi) 
            cs_bar_accel <= 1'b1; // slave select is active low 
        else 
            cs_bar_accel <= ~safe_cs_sel[1];

      always @ (posedge clk)
        if (!reset_spi) 
            cs_bar_disp <= 1'b1; // slave select is active low 
        else
            cs_bar_disp <= ~safe_cs_sel[0];

*/

    
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
      if (!reset_spi) // syncrinus reset 
        currentState <= IDLE;
      else 
        currentState <= nextState;
    end


    // === Next state logic 
    always @ (currentState, tx_begin, countBit, frameBits)
      begin
        nextState = currentState; // default is no change
        case (currentState)
           IDLE:          if (tx_begin) nextState = PREP;
                          else nextState = IDLE;

           PREP:          nextState = TX;
          
           // Tx state loops untill all bits are recived.
           TX:            if (countBit == frameBits) 
                            nextState = COMPLETE; 
                          else 
                            nextState = TX;
                         
           COMPLETE:      nextState = IDLE; 

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
                  dataRx_ready = 1'b0; // when high, byte is ready to be read, transaction is happening
                  clear_countBit = 1'b1; 
                  //cs_bar_accel = 1'b1; // accelerometer slave select (active low)
              end

        PREP:  begin
                  // inital set up before communication
                  is_spi_busy = 1'b1; // so software side knows spi is currently communicating
                  prep_shiftReg = 1'b1; // signals to place data for Rx to slave in shiftReg
                  update_mosi = 1'b0;
                  read_miso = 1'b0;
                  dataRx_ready = 1'b0;
                  //cs_bar_accel = 1'b0; // accelerometer slave select (active low)
                  clear_countBit = 1'b0;  
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
                         dataRx_ready = 1'b0; // byte from slave should NOT be read
                         //cs_bar_accel = 1'b0; // accelerometer slave select (active low)
                         clear_countBit = 1'b0;  
                       end 

                   // Sampling miso on falling edges
                   else if (sclk_falling)
                       begin
                           // When the master samples the slave output, the slave output is shifted into the lowest bit position of shiftReg.
                           //   The shift causes the highst bit to be replaced with the second highest, this means the next bit for the master 
                           //   to send is ready (mosi only updates on even clock edges).
                           is_spi_busy = 1'b1; // so software side knows spi is currently communicating
                           prep_shiftReg = 1'b0;
                           update_mosi = 1'b0;
                           read_miso = 1'b1;
                           dataRx_ready = 1'b0; // byte from slave should NOT be read
                           //cs_bar_accel = 1'b0; // accelerometer slave select (active low)
                           clear_countBit = 1'b0;  
                       end
                   
                   // Default (nothing is done when not on a clock edge)
                   else
                       begin
                           // When the master samples the slave output, the slave output is shifted into the lowest bit position of shiftReg.
                           //   The shift causes the highst bit to be replaced with the second highest, this means the next bit for the master 
                           //   to send is ready (mosi only updates on even clock edges).
                           is_spi_busy = 1'b1; // so software side knows spi is currently communicating
                           prep_shiftReg = 1'b0;
                           update_mosi = 1'b0;
                           read_miso = 1'b0;
                           dataRx_ready = 1'b0; // byte from slave should NOT be read
                           //cs_bar_accel = 1'b0; // accelerometer slave select (active low)
                           clear_countBit = 1'b0;  
                       end
                         
                     
              end


         COMPLETE:    begin
                           is_spi_busy = 1'b1; // so software side knows spi is currently communicating
                           prep_shiftReg = 1'b0; // signals to place data for Rx to slave in shiftReg
                           update_mosi = 1'b0;
                           read_miso = 1'b0;
                           dataRx_ready = 1'b1; // bytes from slave is ready to be read
                           //cs_bar_accel = 1'b1; // accelerometer slave select (active low)
                           clear_countBit = 1'b0;  
                       end

        endcase
    
    // ====== SPI Communication Logic =========
    // MOSI register
    always @ (posedge clk)
        if (!reset_spi)
            mosi <= 1'b0;
        else
            mosi <= nextMosi;
     
    // MUX input to mosi register
    always @ (update_mosi, shiftReg, mosi)
        begin
             if (update_mosi) nextMosi = shiftReg[15];
             else nextMosi = mosi;
        end
    
    // shiftReg register 
    always @ (posedge clk)
        if (!reset_spi) 
            shiftReg <= 16'b0;
        else
            shiftReg <= nextShiftReg;
    
    // MUX to change shiftReg register input 
    always @ (prep_shiftReg, read_miso, dataTx, shiftReg, miso)
        case({prep_shiftReg, read_miso})
            2'b10:    nextShiftReg = {dataTx, 8'b0};
            2'b01:    nextShiftReg = {shiftReg[14:0], miso};
            default: nextShiftReg = shiftReg;
        endcase 
    
    
    reg clear_countBit;  
    // countBit register
    always @ (posedge clk)
        if (!reset_spi) 
            countBit <= 6'b0;
        else
            countBit <= nextCountBit;
    
    // MUX to increase countBit 
    always @ (clear_countBit, read_miso, countBit)
        begin
             if (clear_countBit) nextCountBit = 6'b0;
             else if (read_miso) nextCountBit = countBit + 6'd1;
             else nextCountBit = countBit;
        end
        
        
     // dataRx register - byte from slave
     always @ (posedge clk)
         if (!reset_spi) dataRx <= 16'b0;
         else if (currentState == COMPLETE) dataRx <= shiftReg; 
         else dataRx <= dataRx;
     /*
     // MUX to increase countBit 
    // MUX will only allow the dataRx register (output) to change when a SPI transaction is complete
     always @ (dataRx_ready, shiftReg)
         begin
              if (dataRx_ready) nextDataRx = shiftReg;
              else nextDataRx = dataRx;
         end
         
     */ 
    


    endmodule




            


