library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity controlunit is
    port (
        clk     : in  std_logic;
        instr   : in  std_logic_vector(31 downto 0);
        aluflag : in  std_logic_vector(3 downto 0);
        flagwm  : in  std_logic_vector(3 downto 0);  -- 4-bit: N Z C V

        -- Interrupt lines
        irq_line : in  std_logic;
        fiq_line : in  std_logic;

        -- Standard control outputs
        pcsrc, regwrite, memwrite : out std_logic;
        memtoreg, alusrc : out std_logic;
        immsrc, regsrc   : out std_logic_vector(1 downto 0);
        aluco   : out std_logic_vector(2 downto 0);
        flagw   : out std_logic_vector(3 downto 0);   -- 4-bit: N Z C V

        -- Interrupt control outputs (to datapath)
        irq_taken : out std_logic;   -- IRQ being taken this cycle → flush + redirect
        fiq_taken : out std_logic;   -- FIQ being taken this cycle → flush + redirect
        cpu_mode  : out std_logic_vector(4 downto 0)  -- current mode → regfile banking
    );
end controlunit;

architecture Behavioral of controlunit is

    -- ARM processor mode constants
    constant USER_MODE : std_logic_vector(4 downto 0) := "10000";
    constant FIQ_MODE  : std_logic_vector(4 downto 0) := "10001";
    constant IRQ_MODE  : std_logic_vector(4 downto 0) := "10010";

    -- CPSR mode/mask registers
    signal cpsr_mode : std_logic_vector(4 downto 0) := USER_MODE;
    signal cpsr_i    : std_logic := '0';  -- IRQ mask (0=enabled)
    signal cpsr_f    : std_logic := '0';  -- FIQ mask (0=enabled)

    -- Saved PSR for each interrupt type
    -- Bit layout mirrors ARM CPSR:
    --   [31:28]=NZCV  [7]=I  [6]=F  [4:0]=mode
    signal spsr_irq : std_logic_vector(31 downto 0) := (others => '0');
    signal spsr_fiq : std_logic_vector(31 downto 0) := (others => '0');

    -- Existing internal signals
    signal b_s, m2r_s, mw_s, alusrc_s, regw_s, aluop_s : std_logic;
    signal immsrc_s, regsrc_s : std_logic_vector(1 downto 0);
    signal flagw_s  : std_logic_vector(3 downto 0);
    signal aluco_s  : std_logic_vector(2 downto 0);
    signal pcs_s    : std_logic;
    signal flags_s  : std_logic_vector(3 downto 0) := (others => '0');
    signal nowrite_s : std_logic;
    signal condex_s  : std_logic;

    -- Interrupt internal signals
    signal irq_taken_s  : std_logic;
    signal fiq_taken_s  : std_logic;
    signal instr_is_rti : std_logic;  -- return from interrupt
    signal cpsr_val     : std_logic_vector(31 downto 0);  -- current CPSR for SPSR save

    component maindecoder port(
        a : in std_logic_vector(31 downto 0);
        opcode : in std_logic_vector(1 downto 0);
        funct5, funct0 : in std_logic;
        B, M2R, MW, ALUSrc, RegW, ALUop1 : out std_logic;
        immsrc, regsrc : out std_logic_vector(1 downto 0));
    end component;

    component aludecoder port(
        ALUOp   : in  std_logic;
        funct   : in  std_logic_vector(4 downto 0);
        ALUCO   : out std_logic_vector(2 downto 0);
        Flagw   : out std_logic_vector(3 downto 0);
        nowrite : out std_logic);
    end component;

    component pclogic port(
        Rd   : in  std_logic_vector(3 downto 0);
        regw : in  std_logic;
        b    : in  std_logic;
        pcs  : out std_logic);
    end component;

    component condlogic port(
        clk  : in std_logic;
        cond : in std_logic_vector(3 downto 0);
        flag : in std_logic_vector(3 downto 0);
        pcsrcin, regwritein, memwritein, nowrite : in std_logic;
        flagwin : in std_logic_vector(3 downto 0);
        aluflag : in std_logic_vector(3 downto 0);
        pcsrc, regwrite, memwrite : out std_logic;
        uflags     : out std_logic_vector(3 downto 0);
        condex_out : out std_logic);
    end component;

begin

    -- --------------------------------------------------------
    -- Existing decoder chain (unchanged)
    -- --------------------------------------------------------
    md : maindecoder port map(
        a      => instr,
        opcode => instr(27 downto 26),
        funct5 => instr(25),
        funct0 => instr(20),
        b => b_s, m2r => m2r_s, mw => mw_s,
        alusrc => alusrc_s, regw => regw_s, aluop1 => aluop_s,
        immsrc => immsrc_s, regsrc => regsrc_s);

    ad : aludecoder port map(
        aluop   => aluop_s,
        funct   => instr(24 downto 20),
        aluco   => aluco_s,
        flagw   => flagw_s,
        nowrite => nowrite_s);

    pl : pclogic port map(
        rd   => instr(15 downto 12),
        regw => regw_s,
        b    => b_s,
        pcs  => pcs_s);

    cl : condlogic port map(
        clk        => clk,
        cond       => instr(31 downto 28),
        flag       => flags_s,
        pcsrcin    => pcs_s,
        regwritein => regw_s,
        memwritein => mw_s,
        nowrite    => nowrite_s,
        flagwin    => flagwm,
        aluflag    => aluflag,
        pcsrc      => pcsrc,
        regwrite   => regwrite,
        memwrite   => memwrite,
        uflags     => flags_s,
        condex_out => condex_s);

    -- Flag enables gated with condexs at decode time
    flagw(3) <= flagw_s(3) and condex_s;
    flagw(2) <= flagw_s(2) and condex_s;
    flagw(1) <= flagw_s(1) and condex_s;
    flagw(0) <= flagw_s(0) and condex_s;

    memtoreg <= m2r_s;
    alusrc   <= alusrc_s;
    immsrc   <= immsrc_s;
    regsrc   <= regsrc_s;
    aluco    <= aluco_s;

    -- --------------------------------------------------------
    -- CPSR value construction (for saving to SPSR)
    -- [31:28]=NZCV  [27:8]=0  [7]=I  [6]=F  [5]=0  [4:0]=mode
    -- --------------------------------------------------------
    cpsr_val <= flags_s &
                "00000000000000000000" &
                cpsr_i & cpsr_f & '0' &
                cpsr_mode;

    -- --------------------------------------------------------
    -- Interrupt priority and masking (combinational)
    -- FIQ has higher priority than IRQ
    -- --------------------------------------------------------
    fiq_taken_s <= fiq_line and (not cpsr_f);
    irq_taken_s <= irq_line and (not cpsr_i) and (not fiq_taken_s);

    -- Return from interrupt:
    --   SUBS PC, LR, #4 → pcs_s='1', flagw_s≠0 (S bit), in interrupt mode
    --   The S bit + Rd=R15 is the ARM mechanism for restoring CPSR from SPSR
    instr_is_rti <= '1' when (pcs_s = '1') and
                             (flagw_s /= "0000") and
                             (cpsr_mode /= USER_MODE)
                    else '0';

    -- --------------------------------------------------------
    -- CPSR/SPSR clocked update
    -- --------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if fiq_taken_s = '1' then
                -- FIQ entry: save CPSR, switch to FIQ mode, mask both
                spsr_fiq  <= cpsr_val;
                cpsr_mode <= FIQ_MODE;
                cpsr_i    <= '1';
                cpsr_f    <= '1';

            elsif irq_taken_s = '1' then
                -- IRQ entry: save CPSR, switch to IRQ mode, mask IRQ
                spsr_irq  <= cpsr_val;
                cpsr_mode <= IRQ_MODE;
                cpsr_i    <= '1';
                -- cpsr_f unchanged: FIQ can still preempt IRQ

            elsif instr_is_rti = '1' then
                -- Return from interrupt: restore mode and mask bits from SPSR
                -- Note: flag restoration (NZCV) handled separately via normal
                -- flag write path when SUBS executes - mode/mask restored here
                if cpsr_mode = IRQ_MODE then
                    cpsr_mode <= spsr_irq(4 downto 0);
                    cpsr_i    <= spsr_irq(7);
                    cpsr_f    <= spsr_irq(6);
                elsif cpsr_mode = FIQ_MODE then
                    cpsr_mode <= spsr_fiq(4 downto 0);
                    cpsr_i    <= spsr_fiq(7);
                    cpsr_f    <= spsr_fiq(6);
                end if;
            end if;
        end if;
    end process;

    -- --------------------------------------------------------
    -- Interrupt outputs to datapath
    -- --------------------------------------------------------
    irq_taken <= irq_taken_s;
    fiq_taken <= fiq_taken_s;
    cpu_mode  <= cpsr_mode;

end Behavioral;