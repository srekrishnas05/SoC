library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity imem is
    port (
        addr : in  std_logic_vector(31 downto 0);
        rd   : out std_logic_vector(31 downto 0)
    );
end imem;

architecture Behavioral of imem is
    type imem_t is array (0 to 255) of std_logic_vector(31 downto 0);
    signal mem : imem_t := (

        0  => x"EA00001C",  -- 0x00: B main          (-> 0x20)
        1  => x"EAFFFFFC",  -- 0x04: B . (und stub)
        2  => x"EAFFFFFC",  -- 0x08: B . (swi stub)
        3  => x"EAFFFFFC",  -- 0x0C: B . (prefetch abort)
        4  => x"EAFFFFFC",  -- 0x10: B . (data abort)
        5  => x"E320F000",  -- 0x14: NOP (reserved)
        6  => x"EA000044",  -- 0x18: B irq_handler   (-> 0x60)
        7  => x"EAFFFFFC",  -- 0x1C: B . (FIQ stub)

        8  => x"E2801001",  -- 0x20: ADD R1, R0, #1      R1 = 1
        9  => x"E2802002",  -- 0x24: ADD R2, R0, #2      R2 = 2
        10 => x"E2803004",  -- 0x28: ADD R3, R0, #4      R3 = 4
        11 => x"E2804008",  -- 0x2C: ADD R4, R0, #8      R4 = 8
        12 => x"E2805040",  -- 0x30: ADD R5, R0, #0x40   R5 = 0x40

        -- STMIA R5, {R1-R4}: [0x40]=1,[0x44]=2,[0x48]=4,[0x4C]=8
        13 => x"E885001E",  -- 0x34: STMIA R5, {R1-R4}

        -- LDMIA R5, {R6-R9}: R6=1,R7=2,R8=4,R9=8
        14 => x"E89503C0",  -- 0x38: LDMIA R5, {R6-R9}

        -- STMDB R5!, {R1-R4}: R5->0x30, [0x30..0x3C]={1,2,4,8}
        15 => x"E925001E",  -- 0x3C: STMDB R5!, {R1-R4}

        -- LDMIA R5!, {R1-R4}: R1=1,R2=2,R3=4,R4=8, R5->0x40
        16 => x"E8B5001E",  -- 0x40: LDMIA R5!, {R1-R4}

        17 => x"EAFFFFFC",  -- 0x44: B . (halt loop)

        24 => x"E280A0AB",  -- 0x60: ADD R10, R0, #0xAB  (ISR marker)
        25 => x"E25EF004",  -- 0x64: SUBS PC, LR, #4     (return from IRQ)

        others => x"E320F000"   -- NOP
    );
begin
    rd <= mem(to_integer(unsigned(addr(9 downto 2))));
end Behavioral;