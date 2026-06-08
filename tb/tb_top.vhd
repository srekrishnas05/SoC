library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library STD;
use STD.ENV.ALL;
library XIL_DEFAULTLIB;
use XIL_DEFAULTLIB.all;

entity tb_top is
end tb_top;

architecture Behavioral of tb_top is

    signal clk : std_logic := '0';
    
    -- observation signals
    signal reg1_obs : std_logic_vector(31 downto 0) := (others => '0');
    signal reg2_obs : std_logic_vector(31 downto 0) := (others => '0');
    signal reg3_obs : std_logic_vector(31 downto 0) := (others => '0');

    component top port(
        clk      : in std_logic;
        irq_line : in std_logic;
        fiq_line : in std_logic;
        reg1_out : out std_logic_vector(31 downto 0);
        reg2_out : out std_logic_vector(31 downto 0);
        reg3_out : out std_logic_vector(31 downto 0));
    end component;

begin

    uut : top port map(
        clk      => clk,
        irq_line => '0',   -- no interrupt in this test
        fiq_line => '0',
        reg1_out => reg1_obs,
        reg2_out => reg2_obs,
        reg3_out => reg3_obs);

    clk <= not clk after 5ns;

    process
    begin
        wait;
    end process;

    process
    begin
        wait for 1000 ns;
        assert (reg1_obs = x"00000001")
            report "FAIL: R1 expected 0x1 after LDMIA R5!,{R1-R4}"
            severity failure;

        assert (reg2_obs = x"00000002")
            report "FAIL: R2 expected 0x2 after LDMIA R5!,{R1-R4}"
            severity failure;

        assert (reg3_obs = x"00000040")
            report "FAIL: R5 expected 0x40 after LDMIA writeback"
            severity failure;

        report "PASS: all assertions passed";
        wait;
    end process;

end Behavioral;