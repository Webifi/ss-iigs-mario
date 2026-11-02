"""The asset build: the art, the sound and the data from the ROM files, as
generated sources of the Second Sight and IIgs programs. The Makefile runs
it when its inputs change, then links the programs."""

import area_data
import collision_data
import enemies_data
import objects_data
import player_data
import roms
import screen_data
import secondsight_link
import song_data
import sound_bank
import sprites_data
import tiles
from iigs_payload import Host

ROOT = roms.ROOT


def main():
    program, tile_rom = roms.load()
    tiles.build(tile_rom, program)
    host = Host(ROOT / "build/game")
    screen_data.build(program, host, tile_rom)
    area_data.build(program, host)
    player_data.build(program, host)
    objects_data.build(program, host)
    enemies_data.build(program, host)
    collision_data.build(program, host)
    sprites_data.build(program, host)
    song_data.build(program, host)
    sound_bank.build(host)
    secondsight_link.write_inputs()
    host.save()


if __name__ == "__main__":
    main()
