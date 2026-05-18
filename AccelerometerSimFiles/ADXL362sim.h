/*  Functions to simulate interaction with an ADXL362 accelerometer.
    Writing a value to an accelerometer register will change the
    register if the register is read-write.
    Reading most of the accelerometer registers gives the reset value,
    or the most recent value that you have written to that register.
    The acceleration registers give false values for acceleration:
    X = -345 mg, Z = 876 mg, Y varies in the range +/- 1100 mg.

    To use these functions in CodeBlocks, put these files in the
    project folder: libADXL362sim.a, ADXL362sim.h, typedefs.h.
    On the Project menu, choose Build Options.  Change the
    Linker Settings to add the library file libADXL362sim.a
    Answer No when asked if you want to keep this as a relative path.
    Alternatively, if you want to keep it as a relative path, add
    .\ so that the library file appears as .\libADXL362sim.a
    In your main program, #include this header file and typedefs.h.

    To use these functions in Keil uVision, put these files in the
    project folder: ADXL362sim.lib, ADXL362sim.h.
    Also typedefs.h if you do not have the type definitions
	already (they are in the DES_M0_SoC.h file).
    Add ADXL362sim.lib as a source file in the project.
    In your main program, #include this header file and also
		typedefs.h if you need it.
    */

#include "typedefs.h"  // remove this if you do not need it

// Define names for SPI slaves
#define NONE 0
#define DISP 1
#define ACL  2

/* Function to activate the slave select signal (active low) for
   a specific slave device. Use argument ACL to select the
   ADXL362. Use argument NONE to de-select all slaves. */
void SPIselect ( uint8 slaveNumber );

/* Function to generate 8 clock pulses and transfer 8 bits on
   MOSI and MISO, MSB first. The argument is the byte to send
   on MOSI. The function will not return until the transfer is
   complete. The return value is the byte received on MISO. */
uint8 SPIbyte ( uint8 byteTX );
