### DEAR Shingles

The new SPI master hardware module is in AHBspi.v, I have made some super comments in an attempt to explain how it works, tho i could only sleep for an hour last night so go knows what that module was written like.

The idea is the SPI master has registers specifically for controlling the master. Verilog registers get assigned real memory adresses, so if we can find them we can change the internal registers that are design control the master. So like theres contol registers for tx and rx data and begin tx and stuff, also theres some registers we can read for info on what its up to.

So the plan is to use software to tell the master what slaves to select, commands and adresses to send to them and all that waffle. The master and slaves (i havnet done the dispay yet) are all connected in hardware, so they'll start waffling to each other, but at the end of every transmission session, the Rx data gets put in a register. So we'll use software to rob that information and then do other stuff with it.

Like well probubly use software to tell the master what to get from the acceleromiter, they'll waffle to each other, we'll rangle the Rx data from the register in software, condition it in software to look nice, then use software to gove it back to the master and tell her to send it to the display with spi. 

Bingo Bango Bongo, I don't want to leave the Congo, Oh no no no no noooooo :)

- D' Gnome
