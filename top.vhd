library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity top is
    port (
        clk      : in  std_logic;
        irq_line : in  std_logic;
        fiq_line : in  std_logic;
        reg1_out : out std_logic_vector(31 downto 0);
        reg2_out : out std_logic_vector(31 downto 0);
        reg3_out : out std_logic_vector(31 downto 0)
    );
end top;

architecture Behavioral of top is
    signal instr_s    : std_logic_vector(31 downto 0);
    signal aluflags_s : std_logic_vector(3 downto 0);
    signal pcsrc_s, memtoreg_s, memwrite_s, alusrc_s, regwrite_s : std_logic;
    signal immsrc_s, regsrc_s : std_logic_vector(1 downto 0);
    signal aluco_s  : std_logic_vector(2 downto 0);
    signal flagw_s  : std_logic_vector(3 downto 0);
    signal flagwm_s : std_logic_vector(3 downto 0);

    -- Interrupt wires between controlunit and datapath
    signal irq_taken_s : std_logic;
    signal fiq_taken_s : std_logic;
    signal cpu_mode_s  : std_logic_vector(4 downto 0);
    signal npu_irq_s   : std_logic;
    signal irq_line_s  : std_logic;  -- OR of external irq_line and NPU done

    component controlunit port(
        clk     : in  std_logic;
        instr   : in  std_logic_vector(31 downto 0);
        aluflag : in  std_logic_vector(3 downto 0);
        flagwm  : in  std_logic_vector(3 downto 0);
        irq_line : in  std_logic;
        fiq_line : in  std_logic;
        pcsrc, regwrite, memwrite : out std_logic;
        memtoreg, alusrc : out std_logic;
        immsrc, regsrc   : out std_logic_vector(1 downto 0);
        aluco   : out std_logic_vector(2 downto 0);
        flagw   : out std_logic_vector(3 downto 0);
        irq_taken : out std_logic;
        fiq_taken : out std_logic;
        cpu_mode  : out std_logic_vector(4 downto 0));
    end component;

    component datapath port(
        clk     : in  std_logic;
        flagw   : in  std_logic_vector(3 downto 0);
        pcsrc, memtoreg, memwrite, alusrc, regwrite : in std_logic;
        immsrc, regsrc : in std_logic_vector(1 downto 0);
        aluco   : in  std_logic_vector(2 downto 0);
        instr   : out std_logic_vector(31 downto 0);
        flagwm  : out std_logic_vector(3 downto 0);
        aluflags : out std_logic_vector(3 downto 0);
        irq_taken : in  std_logic;
        fiq_taken : in  std_logic;
        cpu_mode  : in  std_logic_vector(4 downto 0);
        npu_irq  : out std_logic;
        reg1_out : out std_logic_vector(31 downto 0);
        reg2_out : out std_logic_vector(31 downto 0);
        reg3_out : out std_logic_vector(31 downto 0));
    end component;

begin
    irq_line_s <= irq_line or npu_irq_s;

    cu : controlunit port map(
        clk      => clk,
        instr    => instr_s,
        aluflag  => aluflags_s,
        flagwm   => flagwm_s,
        irq_line => irq_line_s,
        fiq_line => fiq_line,
        pcsrc    => pcsrc_s,
        regwrite => regwrite_s,
        memwrite => memwrite_s,
        memtoreg => memtoreg_s,
        alusrc   => alusrc_s,
        immsrc   => immsrc_s,
        regsrc   => regsrc_s,
        aluco    => aluco_s,
        flagw    => flagw_s,
        irq_taken => irq_taken_s,
        fiq_taken => fiq_taken_s,
        cpu_mode  => cpu_mode_s);

    dp : datapath port map(
        clk      => clk,
        flagw    => flagw_s,
        pcsrc    => pcsrc_s,
        memtoreg => memtoreg_s,
        memwrite => memwrite_s,
        alusrc   => alusrc_s,
        regwrite => regwrite_s,
        immsrc   => immsrc_s,
        regsrc   => regsrc_s,
        aluco    => aluco_s,
        instr    => instr_s,
        flagwm   => flagwm_s,
        aluflags => aluflags_s,
        irq_taken => irq_taken_s,
        fiq_taken => fiq_taken_s,
        cpu_mode  => cpu_mode_s,
        npu_irq  => npu_irq_s,
        reg1_out => reg1_out,
        reg2_out => reg2_out,
        reg3_out => reg3_out);

end Behavioral;