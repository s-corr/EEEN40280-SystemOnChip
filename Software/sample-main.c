#include <stdio.h>
#include "DES_M0_SoC.h"

// ==========================  ADXL362 Constants  ============================

#define READ_COM        0x0B    // read-register command
#define WRITE_COM       0x0A    // write-register command

#define REG_FILTER_CTL  0x2C    // filter & range control
#define REG_POWER_CTL   0x2D    // power-mode control
#define REG_DEVID_AD    0x00    // device ID (should read 0xAD)

// 16-bit (14-bit left-justified) data registers — low byte first;
// the ADXL362 auto-increments the internal address while CS is held low.
#define XDATA_L         0x0E
#define XDATA_H         0x0F
#define YDATA_L         0x10
#define YDATA_H         0x11
#define ZDATA_L         0x12
#define ZDATA_H         0x13

// NVIC interrupt bit for the SPI peripheral.
// From AHBliteTop.v: "assign IRQ = {13'b0, IRQ_spi, IRQ_uart, 1'b0}"
//                     IRQ[2] = SPI,   IRQ[1] = UART
#define NVIC_SPI_BIT    2

// ====================  7-Segment Character Codes  ==========================
// Hex-mode character codes from the AHBdisp.v lookup table.
// The table maps a 5-bit value to a 7-segment pattern (active low).
// For values 0x00-0x0F the display shows the hex digit (0-9, A-F).
// For 0x10-0x1B there are special characters; ≥ 0x1C is blank.
//
// Usable letters: A b C d E F  H L n o P r t u y
#define SEG_C   0x0C    // C   (capital)
#define SEG_d   0x0D    // d   (lowercase)
#define SEG_E   0x0E    // E   (capital)
#define SEG_H   0x13    // H   (capital)
#define SEG_L   0x14    // L   (capital)
#define SEG_n   0x15    // n   (lowercase)
#define SEG_o   0x16    // o   (lowercase)
#define SEG_r   0x18    // r   (lowercase)
#define SEG_t   0x19    // t   (lowercase)
#define SEG_u   0x1A    // u   (lowercase)
#define SEG_1   0x01    // 1
#define SEG_2   0x02    // 2
#define SEG_3   0x03    // 3
#define SEG_MIN 0x11    // middle-bar minus sign
#define SEG_BL  0x1F    // blank (any value ≥ 0x1C)

// ==================  SPI Interrupt State Machine  ==========================
//
// The SPI ISR sequences a multi-byte register read from the ADXL362 without
// polling the Status register.  Each interrupt fires when a single 8-bit
// frame finishes (dataRx_ready = 1 in the SPI master's COMPLETE state).
//
// Pipeline delay (documented in spi.v):
//   The slave's MISO output lags by one byte — the byte received during
//   frame N is the slave's response to the byte transmitted in frame N-1.
//
//   Therefore reading two bytes (XDATA_L, XDATA_H via auto-increment)
//   needs 4 frames in a single CS-session:
//
//     Frame   Tx byte            Rx byte (read in next ISR)
//     ─────   ───────            ────────────────────────────
//       1     READ_COM (0x0B)    garbage (slave latches cmd)
//       2     register address   status/echo
//       3     dummy (0x00)       XDATA_L  ← received here (pipeline)
//       4     dummy (0x00)       XDATA_H  ← received here
//
//   The ISR state machine:
//     phase 0 → after frame 1: send register address
//     phase 1 → after frame 2: send first dummy
//     phase 2 → after frame 3: save XDATA_L, send second dummy
//     phase 3 → after frame 4: save XDATA_H, deassert CS, done

volatile uint8  spi_phase;      // ISR state (0..3)
volatile uint8  accel_lo;       // received low  byte of the 16-bit reading
volatile uint8  accel_hi;       // received high byte of the 16-bit reading
volatile uint8  axis_addr;      // register address to read (XDATA_L / YDATA_L / ZDATA_L)
volatile int16  accel_result;   // assembled & right-justified 14-bit signed value (mg)
volatile uint8  data_ready;     // set by ISR when all 4 frames are complete

// ========================  SPI Interrupt Handler  ==========================

void SPI_ISR(void) {
    uint8 rx = (uint8)pt2SPI->RxData;

    switch (spi_phase) {
        case 0:                                     // frame 1 (READ_COM) done
            pt2SPI->TxData = axis_addr;             // send register address
            pt2SPI->EnSpi = 1;                      // start next frame
            spi_phase = 1;
            break;

        case 1:                                     // frame 2 (address) done
            pt2SPI->TxData = 0x00;                  // send first dummy
            pt2SPI->EnSpi = 1;
            spi_phase = 2;
            break;

        case 2:                                     // frame 3 done → rx = XDATA_L
            accel_lo = rx;                          // save low byte
            pt2SPI->TxData = 0x00;                  // send second dummy
            pt2SPI->EnSpi = 1;                      // → returns XDATA_H next frame
            spi_phase = 3;
            break;

        case 3:                                     // frame 4 done → rx = XDATA_H
            accel_hi = rx;                          // save high byte
            pt2SPI->AclSel = 0;                     // deassert chip select
            spi_phase = 0;                          // reset for next read cycle

            // The ADXL362 stores acceleration as a 14-bit left-justified value
            // in a 16-bit register (bits 15:2 = data, bits 1:0 = 0).
            // Right-shift by 2 to obtain the signed mg value.
            accel_result = ((int16)((accel_hi << 8) | accel_lo)) >> 2;
            data_ready = 1;
            break;
    }
}

// ========================  Utility Functions  ==============================

static void delay(volatile uint32 n) {
    while (n--);
}

// Blocking SPI byte transfer — used only during one-time setup before the
// interrupt-driven read loop takes over.
static void poll_xfer(uint8 tx) {
    pt2SPI->TxData = tx;
    pt2SPI->EnSpi = 1;
    while (pt2SPI->Status & (1 << SPI_IS_SPI_BUSY));
}

// ========================  Display Functions  ==============================
//
// displayReg[x] maps directly to the AHBdisp hardware registers:
//   [0..7]  = digit data (0 = rightmost, 7 = leftmost)
//   [8]     = mode for each digit  (0 = raw, 1 = hex)
//   [9]     = enable for each digit (0 = off, 1 = on)
//
// In hex mode, the hardware lookup table converts a 5-bit value to the
// 7-segment pattern.  The available characters are listed above.

// Show the numeric acceleration value on the right four digits.
// Format:  s D2 D1 D0  (sign, hundreds, tens, units)
// Example: "-123    "  or " 456    "
static void disp_value(int16 val) {
    uint8 neg = 0;
    if (val < 0) { neg = 1; val = -val; }
    if (val > 999) val = 999;

    // Rightmost 4 digits: sign + 3-digit value
    displayReg[0] = val % 10;   val /= 10;      // units   (rightmost)
    displayReg[1] = val % 10;   val /= 10;      // tens
    displayReg[2] = val;                         // hundreds
    displayReg[3] = neg ? SEG_MIN : SEG_BL;     // minus or blank

    // Leftmost 4 digits blank
    displayReg[4] = SEG_BL;
    displayReg[5] = SEG_BL;
    displayReg[6] = SEG_BL;
    displayReg[7] = SEG_BL;

    displayReg[8] = 0xFF;       // hex mode for all 8 digits
    displayReg[9] = 0xFF;       // all 8 digits enabled
}

// Show an axis label "CHn    " for 2 seconds after a switch change.
//   n = 1 (X), 2 (Y), or 3 (Z)
// The three available letters (C, H, plus digit 1-3) fit within 8 digits.
static void disp_label(uint8 axis) {
    displayReg[7] = SEG_C;              // C  (leftmost digit)
    displayReg[6] = SEG_H;              // H
    displayReg[5] = (axis == 1) ? SEG_1 :
                    (axis == 2) ? SEG_2 : SEG_3;
    displayReg[4] = SEG_BL;
    displayReg[3] = SEG_BL;
    displayReg[2] = SEG_BL;
    displayReg[1] = SEG_BL;
    displayReg[0] = SEG_BL;

    displayReg[8] = 0xFF;
    displayReg[9] = 0xFF;
}

// Show "Error  " when more than one switch is on (one-hot violation).
// The hex-mode characters for "Error" are all available: E r r o r.
static void disp_error(void) {
    displayReg[7] = SEG_E;
    displayReg[6] = SEG_r;
    displayReg[5] = SEG_r;
    displayReg[4] = SEG_o;
    displayReg[3] = SEG_r;
    displayReg[2] = SEG_BL;
    displayReg[1] = SEG_BL;
    displayReg[0] = SEG_BL;

    displayReg[8] = 0xFF;
    displayReg[9] = 0xFF;
}

// =================  Main Application States  ===============================
// The main loop can be in one of three states based on the switch inputs.
enum { STATE_DATA,       // one switch on, past the 2 s label period
       STATE_LABEL,      // one switch on, showing axis name for 2 s
       STATE_ERROR }     // more than one switch on (one-hot violation)
       state;

// ================================  Main  ===================================

int main(void) {
    uint16 sw;
    uint16 prev_sw = 0;         // previous switch value for edge detection
    uint8  axis_active = 3;     // currently selected axis (1=X, 2=Y, 3=Z)
    uint8  label_cnt = 0;       // counts ~100 ms ticks for the 2 s label

    delay(100000);
    printf("\nSoC Accelerometer Display\n");

    // ----  SPI peripheral initialisation  ---------------------------------
    // Register map (AHBspi.v): HADDR[3:1] selects one of 8 byte-wide regs.
    pt2SPI->ClkDelay = 4;       // SCLK = 50 MHz / (2*(4+1)) = 5 MHz
    pt2SPI->FrameBits = 8;      // 8-bit frames
    pt2SPI->AclSel = 0;         // chip select inactive
    pt2SPI->Control = 0x02;     // enable dataRx_ready interrupt
    NVIC_Enable = (1 << NVIC_SPI_BIT);  // SPI IRQ in NVIC

    // ----  Accelerometer initialisation  ----------------------------------
    uint8 id;
    pt2SPI->AclSel = 1;
    poll_xfer(READ_COM);        // send read-command byte
    poll_xfer(REG_DEVID_AD);    // send DEVID_AD (0x00)
    poll_xfer(0x00);            // dummy — pipeline, third transfer gets the value
    id = (uint8)pt2SPI->RxData;
    pt2SPI->AclSel = 0;
    printf("Accel ID: 0x%02X\n", id);   // expected 0xAD

    // Write 0x13 → FILTER_CTL: ±2 g range, 100 Hz ODR
    pt2SPI->AclSel = 1;
    poll_xfer(WRITE_COM);  poll_xfer(REG_FILTER_CTL);  poll_xfer(0x13);
    pt2SPI->AclSel = 0;

    // Write 0x02 → POWER_CTL: measurement mode
    pt2SPI->AclSel = 1;
    poll_xfer(WRITE_COM);  poll_xfer(REG_POWER_CTL);  poll_xfer(0x02);
    pt2SPI->AclSel = 0;

    state = STATE_DATA;         // start in data-display mode

    // ----  Main control loop  ---------------------------------------------
    while (1) {
        // Read the three axis-select switches (SW0, SW1, SW2 on the Nexys4).
        // With a one-hot code: exactly one should be on at a time.
        sw = GPIO_SW & 0x07;

        // Count how many of the three bits are set.
        uint8 cnt = (sw & 1) + ((sw >> 1) & 1) + ((sw >> 2) & 1);

        // ────  Switch validation & state transitions  ──────────────────

        if (cnt > 1) {
            // One-hot violation — show error until the user fixes the switches.
            state = STATE_ERROR;
            disp_error();

        } else if (cnt == 1) {
            // Exactly one switch: determine which axis it requests.
            uint8 axis = (sw & 1) ? 1 : ((sw >> 1) & 1) ? 2 : 3;

            // Show the axis label in three situations:
            //   a) coming out of the ERROR state (user fixed the switches)
            //   b) axis selection changed (user flipped to a different axis)
            //   c) rising edge on any switch (user just turned one on)
            if (state == STATE_ERROR || axis != axis_active ||
                (sw & ~prev_sw)) {
                axis_active = axis;
                label_cnt = 0;
                state = STATE_LABEL;
            }

            if (state == STATE_LABEL) {
                disp_label(axis_active);
                label_cnt++;                    // each iteration ≈ 100 ms
                if (label_cnt >= 20)            // ~2 seconds elapsed
                    state = STATE_DATA;
            }

            if (state == STATE_DATA) {
                // ──  Interrupt-driven accelerometer read  ──────────────
                // Kick off the 4-frame read sequence; the ISR handles
                // the rest and sets data_ready when finished.
                if (axis_active == 1)      axis_addr = XDATA_L;
                else if (axis_active == 2) axis_addr = YDATA_L;
                else                       axis_addr = ZDATA_L;

                data_ready = 0;
                spi_phase = 0;
                pt2SPI->AclSel = 1;             // assert chip select
                pt2SPI->TxData = READ_COM;       // first frame (starts the pipeline)
                pt2SPI->EnSpi = 1;

                while (!data_ready);             // wait for ISR to finish

                disp_value(accel_result);
            }

        } else {
            // cnt == 0 — no axis switch is on.
            // Return to data display using the last valid axis.
            state = STATE_DATA;
            if (axis_active == 1)      axis_addr = XDATA_L;
            else if (axis_active == 2) axis_addr = YDATA_L;
            else                       axis_addr = ZDATA_L;

            data_ready = 0;
            spi_phase = 0;
            pt2SPI->AclSel = 1;
            pt2SPI->TxData = READ_COM;
            pt2SPI->EnSpi = 1;

            while (!data_ready);
            disp_value(accel_result);
        }

        prev_sw = sw;                           // for edge detection next time
        delay(500000);                          // ≈ 100 ms per iteration
    }
}
