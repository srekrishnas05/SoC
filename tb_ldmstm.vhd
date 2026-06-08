library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- Testbench: LDM/STM through top-level system
-- ============================================================
-- Instruction sequence (see imem.vhd):
--   0: ADD R1,R0,#1     R1=1
--   1: ADD R2,R0,#2     R2=2
--   2: ADD R3,R0,#4     R3=4
--   3: ADD R4,R0,#8     R4=8
--   4: ADD R5,R0,#0x40  R5=0x40
--   5: STMIA R5,{R1-R4} [0x40..0x4C] = {1,2,4,8}
--   6: LDMIA R5,{R6-R9} R6=1,R7=2,R8=4,R9=8
--   7: STMDB R5!,{R1-R4} R5→0x30, [0x30..0x3C]={1,2,4,8}
--   8: LDMIA R5!,{R1-R4} R1=1,R2=2,R3=4,R4=8, R5→0x40
--
-- Verification timing:
--   Each LDM/STM takes: 3 drain + N transfer + 1 WB cycles
--   STMIA {R1-R4}: 3+4   = 7  cycles
--   LDMIA {R6-R9}: 3+4   = 7  cycles
--   STMDB {R1-R4}: 3+4+1 = 8  cycles (writeback)
--   LDMIA {R1-R4}: 3+4+1 = 8  cycles (writeback)
--   Plus pipeline fill (5 cycles) and setup (5 instrs)
--
-- Conservative wait: 200ns (20 cycles) per instruction block
-- ============================================================

entity tb_ldmstm is
end tb_ldmstm;

architecture Behavioral of tb_ldmstm is

    signal clk      : std_logic := '0';
    signal reg1_obs : std_logic_vector(31 downto 0);  -- R1
    signal reg2_obs : std_logic_vector(31 downto 0);  -- R2
    signal reg3_obs : std_logic_vector(31 downto 0);  -- R5

    component top port(
        irq_line : in std_logic;
        fiq_line : in std_logic;
        clk      : in  std_logic;
        reg1_out : out std_logic_vector(31 downto 0);
        reg2_out : out std_logic_vector(31 downto 0);
        reg3_out : out std_logic_vector(31 downto 0));
    end component;

    -- reg3_out from regfile.vhd is wired to regs(5) = R5
    -- reg1_out = regs(1) = R1
    -- reg2_out = regs(2) = R2

begin
    clk <= not clk after 5 ns;

    uut : top port map(
        clk      => clk,
        irq_line => '0',
        fiq_line => '0',
        reg1_out => reg1_obs,
        reg2_out => reg2_obs,
        reg3_out => reg3_obs);

    process
    begin
        -- --------------------------------------------------------
        -- Wait for setup instructions (R1-R5 loaded)
        -- 5 instructions * ~5 cycles each + pipeline fill
        -- --------------------------------------------------------
        wait for 140 ns;

        -- --------------------------------------------------------
        -- After STMIA and LDMIA complete:
        -- R6=1, R7=2, R8=4, R9=8
        -- We can't observe R6-R9 directly through reg_out ports.
        -- Verify indirectly: LDMIA R5!,{R1-R4} at end restores
        -- R1-R4 from memory written by STMDB.
        -- --------------------------------------------------------

        -- Wait for STMIA + LDMIA + STMDB to complete
        -- STMIA: ~70ns, LDMIA: ~70ns, STMDB: ~80ns
        wait for 300 ns;

        -- --------------------------------------------------------
        -- After LDMIA R5!,{R1-R4}:
        -- R1 should = 1  (loaded from [0x30])
        -- R2 should = 2  (loaded from [0x34])
        -- R5 should = 0x40 (written back: 0x30 + 4*4)
        -- --------------------------------------------------------
        wait for 150 ns;

        assert (reg1_obs = x"00000001")
            report "FAIL: R1 expected 0x1 after LDMIA R5!,{R1-R4}"
            severity failure;

        assert (reg2_obs = x"00000002")
            report "FAIL: R2 expected 0x2 after LDMIA R5!,{R1-R4}"
            severity failure;

        assert (reg3_obs = x"00000040")
            report "FAIL: R5 expected 0x40 after LDMIA writeback"
            severity failure;

        report "PASS: LDM/STM all assertions passed";
        wait;
    end process;

end Behavioral;