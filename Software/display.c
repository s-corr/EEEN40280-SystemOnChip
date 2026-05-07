#include <stdio.h>
#include "display.h"

void displayAccel(uint16 accel){
	int indexer;
	if (accel >  1000) accel =  1000;
	if (accel < -1000) accel = -1000;
	indexer = (accel + 1000) * 15 / 2000; // This will map the range from -1000 -> 1000 to 0 -> 15
	GPIO_LED = (uint16)(1 << indexer);
}
