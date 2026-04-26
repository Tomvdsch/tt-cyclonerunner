# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

PMOD_LATCH = 1 << 4
PMOD_CLK   = 1 << 5
PMOD_DATA  = 1 << 6

BTN_B      = 1 << 11
BTN_Y      = 1 << 10
BTN_SELECT = 1 << 9
BTN_START  = 1 << 8
BTN_UP     = 1 << 7
BTN_DOWN   = 1 << 6
BTN_LEFT   = 1 << 5
BTN_RIGHT  = 1 << 4
BTN_A      = 1 << 3
BTN_X      = 1 << 2
BTN_L      = 1 << 1
BTN_R      = 1 << 0

def get_hsync(uo_out):
    return (int(uo_out) >> 7) & 1

def get_vsync(uo_out):
    return (int(uo_out) >> 3) & 1

def has_rtl_game_state(dut):
    try:
        _ = dut.user_project.u_game_state
        return True
    except AttributeError:
        return False

async def gamepad_send_buttons(dut, buttons):
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 4)

    for bit_index in range(11, -1, -1):
        bit = (buttons >> bit_index) & 1

        dut.ui_in.value = PMOD_DATA if bit else 0
        await ClockCycles(dut.clk, 4)

        dut.ui_in.value = (PMOD_DATA if bit else 0) | PMOD_CLK
        await ClockCycles(dut.clk, 4)

        dut.ui_in.value = PMOD_DATA if bit else 0
        await ClockCycles(dut.clk, 4)

    dut.ui_in.value = PMOD_LATCH
    await ClockCycles(dut.clk, 4)

    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 4)

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us, 100 KHz.
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset.
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 10)

    dut.rst_n.value = 1

    await ClockCycles(dut.clk, 5)

    dut._log.info("Test project behavior")

    assert int(dut.uio_oe.value) == 0x80

    assert get_hsync(dut.uo_out.value) == 1
    assert get_vsync(dut.uo_out.value) == 1

    hsync_seen_high = False
    hsync_seen_low = False

    for _ in range(800):
        await ClockCycles(dut.clk, 1)
        hsync = get_hsync(dut.uo_out.value)

        if hsync:
            hsync_seen_high = True
        else:
            hsync_seen_low = True

    assert hsync_seen_high
    assert hsync_seen_low

    dut._log.info("Send START button through ui_in gamepad pins")

    await gamepad_send_buttons(dut, BTN_START)

    # game_state only samples buttons on frame_tick.
    # One VGA frame is 800 * 525 clock cycles.
    await ClockCycles(dut.clk, 800 * 525 + 10)

    if has_rtl_game_state(dut):
        assert int(dut.user_project.u_game_state.state.value) == 1
    else:
        dut._log.info("Skipping internal state check in gate-level simulation")

    dut._log.info("Send UP button through ui_in gamepad pins")

    await gamepad_send_buttons(dut, BTN_UP)

    await ClockCycles(dut.clk, 800 * 525 + 10)

    if has_rtl_game_state(dut):
        assert int(dut.user_project.u_game_state.player_y.value) < 84
    else:
        dut._log.info("Skipping internal player_y check in gate-level simulation")
