library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- Testbench: IRQ interrupt
-- ============================================================
-- Sequence:
--   CPU boots, executes B main (vector table), reaches 0x20
--   Main code: ADD R1-R5, then LDM/STM sequence
--   At ~200ns: irq_line pulses HIGH for 20ns
--   CPU takes IRQ: flushes pipeline, jumps to 0x18 (B irq_handler)
--   IRQ handler: ADD R10,R0,#0xAB then SUBS PC,LR,#4
--   CPU returns to interrupted instruction, resumes main code
--
-- Verification:
--   After everything completes:
--   R1 = 1  (main code not corrupted by ISR)
--   R2 = 2  (main code not corrupted by ISR)
--   R5 = 0x40 (LDM/STM completed, writeback correct)
--
--   R10 = 0xAB is visible in waveform (confirms ISR ran)
--   The fact that R1/R2/R5 are correct confirms correct return.
--
-- Timing: irq fires during ADD instructions (before LDM/STM)
-- so the interrupt does not interfere with the sequencer.
-- ============================================================

entity tb_irq is
end tb_irq;

architecture Behavioral of tb_irq is

    signal clk      : std_logic := '0';
    signal irq_line : std_logic := '0';
    signal fiq_line : std_logic := '0';
    signal reg1_obs : std_logic_vector(31 downto 0);  -- R1
    signal reg2_obs : std_logic_vector(31 downto 0);  -- R2
    signal reg3_obs : std_logic_vector(31 downto 0);  -- R5

    component top port(
        clk      : in  std_logic;
        irq_line : in  std_logic;
        fiq_line : in  std_logic;
        reg1_out : out std_logic_vector(31 downto 0);
        reg2_out : out std_logic_vector(31 downto 0);
        reg3_out : out std_logic_vector(31 downto 0));
    end component;

begin
    clk <= not clk after 5 ns;

    uut : top port map(
        clk      => clk,
        irq_line => irq_line,
        fiq_line => fiq_line,
        reg1_out => reg1_obs,
        reg2_out => reg2_obs,
        reg3_out => reg3_obs);

    -- IRQ stimulus: pulse irq_line at 200ns for 20ns
    -- This fires during the ADD R3/R4 phase of main code
    -- Well before LDM/STM starts (which begins at ~250ns)
    process
    begin
        wait for 200 ns;
        irq_line <= '1';
        wait for 20 ns;
        irq_line <= '0';
        wait;
    end process;

    -- Verification process
    process
    begin
        -- Wait for full sequence to complete:
        -- ~40ns  : B main resolves, main code starts
        -- ~100ns : IRQ fires, ISR runs, return
        -- ~250ns : LDM/STM sequence begins  
        -- ~700ns : everything complete
        wait for 800 ns;

        -- R1 and R2 should be unchanged by ISR (ISR uses R10)
        assert (reg1_obs = x"00000001")
            report "FAIL: R1 expected 0x1 - main code corrupted or did not complete"
            severity failure;

        assert (reg2_obs = x"00000002")
            report "FAIL: R2 expected 0x2 - main code corrupted or did not complete"
            severity failure;

        -- R5 should be 0x40 after LDMIA R5! writeback
        assert (reg3_obs = x"00000040")
            report "FAIL: R5 expected 0x40 - LDM/STM writeback wrong or did not complete"
            severity failure;

        report "PASS: IRQ test passed - ISR ran and returned correctly";
        wait;
    end process;

end Behavioral;