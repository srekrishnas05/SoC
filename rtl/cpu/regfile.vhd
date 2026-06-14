library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;



entity regfile is
    port (
        clk      : in std_logic;
        cpu_mode : in std_logic_vector(4 downto 0);  -- current processor mode

        -- Normal pipeline read ports (mode-aware)
        raddr1 : in  std_logic_vector(4 downto 0);
        rdata1 : out std_logic_vector(31 downto 0);
        raddr2 : in  std_logic_vector(4 downto 0);
        rdata2 : out std_logic_vector(31 downto 0);
        r15    : in  std_logic_vector(31 downto 0);  -- PC+8 from datapath

        -- Normal pipeline write port (mode-aware)
        we     : in  std_logic;
        waddr  : in  std_logic_vector(4 downto 0);
        wdata  : in  std_logic_vector(31 downto 0);

        -- Direct banked LR writes for interrupt entry
        -- Bypasses pipeline - written atomically when interrupt fires
        irq_lr_we    : in std_logic;
        irq_lr_wdata : in std_logic_vector(31 downto 0);  -- PC+4 on IRQ entry
        fiq_lr_we    : in std_logic;
        fiq_lr_wdata : in std_logic_vector(31 downto 0);  -- PC+4 on FIQ entry

        -- Observation ports for testbench
        reg1_out : out std_logic_vector(31 downto 0);  -- R1
        reg2_out : out std_logic_vector(31 downto 0);  -- R2
        reg3_out : out std_logic_vector(31 downto 0)   -- R5
    );
end regfile;

architecture Behavioral of regfile is

    -- Mode constants (ARM encoding)
    constant USER_MODE : std_logic_vector(4 downto 0) := "10000";
    constant FIQ_MODE  : std_logic_vector(4 downto 0) := "10001";
    constant IRQ_MODE  : std_logic_vector(4 downto 0) := "10010";
    constant SVC_MODE  : std_logic_vector(4 downto 0) := "10011";

    type reg_array_t is array(0 to 31) of std_logic_vector(31 downto 0);

    -- User/System mode registers (R0-R14)
    signal regs     : reg_array_t := (others => (others => '0'));

    -- IRQ mode banked registers (R13_irq, R14_irq)
    signal regs_irq : reg_array_t := (others => (others => '0'));

    -- FIQ mode banked registers (R8-R14_fiq)
    signal regs_fiq : reg_array_t := (others => (others => '0'));

    -- Helper: is register r banked in IRQ mode?
    function irq_banked(r : integer) return boolean is
    begin
        return (r = 13) or (r = 14);
    end function;

    -- Helper: is register r banked in FIQ mode?
    function fiq_banked(r : integer) return boolean is
    begin
        return (r >= 8) and (r <= 14);
    end function;

begin
    process(all)
        variable wa : integer;
    begin
        wa := to_integer(unsigned(waddr));
        regs(0) <= (others => '0');  -- R0 hardwired to 0

        if (we = '1') and (wa /= 0) and (wa /= 15) then
            if cpu_mode = IRQ_MODE and irq_banked(wa) then
                regs_irq(wa) <= wdata;
            elsif cpu_mode = FIQ_MODE and fiq_banked(wa) then
                regs_fiq(wa) <= wdata;
            else
                regs(wa) <= wdata;
            end if;
        end if;

        -- Direct interrupt entry writes to banked LR
        -- These bypass mode check - always write to the banked register
        if irq_lr_we = '1' then
            regs_irq(14) <= irq_lr_wdata;
        end if;
        if fiq_lr_we = '1' then
            regs_fiq(14) <= fiq_lr_wdata;
        end if;
    end process;

    process(all)
        variable ra1, ra2 : integer;
    begin
        ra1 := to_integer(unsigned(raddr1));
        ra2 := to_integer(unsigned(raddr2));

        -- Read port 1
        if ra1 = 0 then
            rdata1 <= (others => '0');
        elsif ra1 = 15 then
            rdata1 <= r15;
        elsif cpu_mode = IRQ_MODE and irq_banked(ra1) then
            rdata1 <= regs_irq(ra1);
        elsif cpu_mode = FIQ_MODE and fiq_banked(ra1) then
            rdata1 <= regs_fiq(ra1);
        else
            rdata1 <= regs(ra1);
        end if;

        -- Read port 2
        if ra2 = 0 then
            rdata2 <= (others => '0');
        elsif ra2 = 15 then
            rdata2 <= r15;
        elsif cpu_mode = IRQ_MODE and irq_banked(ra2) then
            rdata2 <= regs_irq(ra2);
        elsif cpu_mode = FIQ_MODE and fiq_banked(ra2) then
            rdata2 <= regs_fiq(ra2);
        else
            rdata2 <= regs(ra2);
        end if;
    end process;

    -- Observation ports (always user-mode physical registers)
    reg1_out <= regs(1);
    reg2_out <= regs(2);
    reg3_out <= regs(5);

end Behavioral;