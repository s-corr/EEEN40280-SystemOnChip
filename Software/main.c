/*--------------------------------------------------------------------------------------------------
	Demonstration program for Cortex-M0 SoC design - basic version, no CMSIS

	Enable the interrupt for UART - interrupt when a character is received.
	Repeat:
	  Set the LEDs to match the switches, then flash the 8 rightmost LEDs.
	  Go to sleep mode, waiting for an interrupt
		  On UART interrupt, the ISR sends the received character back to UART and stores it
			  main() also shows the character code on the 8 rightmost LEDs
	  When a whole message has been received, the stored characters are copied to another array
		  with their case inverted, then printed. 

	Version 6 - March 2023
  ------------------------------------------------------------------------------------------------*/

#include <stdio.h>					// needed for printf
#include "DES_M0_SoC.h"			// defines registers in the hardware blocks used
#include "accel.h"
#include "display.h"

#define BUF_SIZE						100				// size of the array to hold received characters
#define ASCII_CR						'\r'			// character to mark the end of input
#define CASE_BIT						('A' ^ 'a')		// bit pattern used to change the case of a letter
#define FLASH_DELAY					1000000		// delay for flashing LEDs, ~220 ms

#define INVERT_LEDS					(GPIO_LED ^= 0xff)		// inverts the 8 rightmost LEDs

#define ARRAY_SIZE(__x__)   (sizeof(__x__)/sizeof(__x__[0]))  // macro to find array size

// Global variables - shared between main and UART_ISR
volatile uint8  RxBuf[BUF_SIZE];	// array to hold received characters
volatile uint8  counter  = 0; 		// current number of characters in RxBuf[]
volatile uint8  BufReady = 0; 		// flag indicates data in RxBuf is ready for processing


//////////////////////////////////////////////////////////////////
// Interrupt service routine, runs when UART interrupt occurs - see cm0dsasm.s
//////////////////////////////////////////////////////////////////
void UART_ISR()		
{
	char c;
	c = UART_RXD;	 				// read character from UART (there must be one waiting)
	RxBuf[counter]  = c;  // store in buffer
	counter++;            // increment counter, number of characters in buffer
	UART_TXD = c;  				// write character to UART (assuming transmit queue not full)

	/* Counter is now the position in the buffer that the next character should go into.
		If this is the end of the buffer, i.e. if counter == BUF_SIZE-1, then null terminate
		and indicate that a complete sentence has been received.
		If the character just put in was a carriage return, do the same.  */
	if (counter == BUF_SIZE-1 || c == ASCII_CR)  
	{
		counter--;							// decrement counter (CR will be over-written)
		RxBuf[counter] = NULL;  // null terminate to make the array a valid string
		BufReady       = 1;	    // indicate that data is ready for processing
	}
}


//////////////////////////////////////////////////////////////////
// Interrupt service routine for System Tick interrupt
//////////////////////////////////////////////////////////////////
void SysTick_ISR()	
{
	// Do nothing - this interrupt is not used here
}


//////////////////////////////////////////////////////////////////
// Software delay function - delay time proportional to argument n
// As a rough guide, delay(1000) takes 160 us to 220 us, 
// depending on the compiler optimisation level.
//////////////////////////////////////////////////////////////////
void delay (uint32 n) 
{
	volatile uint32 i;
		for(i=0; i<n; i++);		// do nothing n times
}


//////////////////////////////////////////////////////////////////
// Main Function
//////////////////////////////////////////////////////////////////
int main(void) 
{
	uint16 accelDataPacket;
	uint8 i;		// used in for loop
	uint8 TxBuf[ARRAY_SIZE(RxBuf)];		// serial transmit buffer

// ========================  Initialisation ==========================================

	// Configure the UART - the control register decides which events cause interrupts
	UART_CTL = (1 << UART_RX_FIFO_NOTEMPTY_BIT_POS);	// enable rx data available interrupt only
	
	// Configure the interrupt system in the processor (NVIC)
	NVIC_Enable = (1 << NVIC_UART_BIT_POS);		// Enable the UART interrupt
	
	delay(FLASH_DELAY);												// wait a short time
	
	printf("\n\nWelcome to Cortex-M0 SoC\n");		// print a welcome message
	printf("\n\nModified Version - Sam and Sean\n\n"); // Print the addition to the welcome message
	
	// INIT SPI
	SPIinit(void);
	
	// INIT ACCEL
	setupAccel(void);


// ========================  Working Loop ==========================================
	
	while(1)		// loop forever
	{	
		// TODO: SEE WHAT CAN GO
		// ---- Start of critical section ----
		// NVIC_Disable = (1 << NVIC_UART_BIT_POS);	// disable the UART interrupt

		// Reset the counter and the flag, ready for the next time
		// counter  = 0; 		// reset the counter	
		// BufReady = 0;			// clear the flag
		
		// NVIC_Enable = (1 << NVIC_UART_BIT_POS);		// Enable the UART interrupt
		// ---- End of critical section ----	
		accelDataPacket = accelRead(0x0E); // Lets just read the acceleration going left for now
		
		printf("\nPACKET RECV : %d\n", (int)accelDataPacket);

		dispalyAccel(accelDataPacket);
		delay(FLASH_DELAY);

	} // end of infinite loop

}  // end of main
