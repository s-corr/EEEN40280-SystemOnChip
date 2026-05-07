#include <stdio.h>
#include "accel.h"
#include "spi.h"



uint8 accelReadReg(uint8 addr){
	uint8 retVal;
	SPIselect(0); // Assert CS low
	SPIbyte(READ_COM); // Send the read command
	SPIbyte(addr); // then send the address to read from
	retVal = SPIbyte(0x00); // Write zeros to shift the returned value back out
	SPIselect(1); // Assert CS high to end transaction
				  
	return retVal; // return the value 
}

void setupAccel(void) {
	uint8 id = accelReadReg(DEVID_AD); // Should read 0xAD for analog devices, get it ahahaha
	printf("ID VALUE = 0x%02X\n", id);

	accelReadReg(FILTER_CTL, 0x13); // Set to +-2g range, 100 Hz output
	accelWriteReg(POWER_CTL, 0x02); // Measurement Mode
}

uint16 accelRead(uint8 axisRegister) {
	uint8 highSide, lowSide;

	SPIselect(0);
	SPIbyte(READ_COM);
	SPIbyte(axisRegister);
	
	lowSide = SPIbyte(0x00);
	highSide = SPIbyte(0x00);
	SPIselect(1);

	return (uint16) ((highSide << 8) | lowSide);
}


void accelWriteReg(uint8 addr, uint8 value) {
	SPIselect(0);
	SPIbyte(WRITE_COM);
	SPIbyte(addr);
	SPIbyte(value);
	SPIselect(1);
}

