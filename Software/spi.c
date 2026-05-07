#include <stdio.h>
#include "spi.h"

void spiCS(int value) {
	SPI_CSn = value; // Write the value to chip select
}

uint8 spiWrite(uint8 byte) {
	SPI_DATA = byte; // Write the 8 bit byte to the spi interface
					 // this will automatically start the transaction
					 // I hope ...
	
	while(SPI_STATUS & 1); // Hold for the busy bit to clear
	return SPI_DATA;  // Then return the data from the data register

}
