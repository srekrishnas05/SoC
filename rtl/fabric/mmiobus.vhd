library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
 
entity mmio_bus is
    port (
        clk       : in  std_logic;
 
        -- From CPU cache (M stage)
        addr      : in  std_logic_vector(31 downto 0);
        wdata     : in  std_logic_vector(31 downto 0);
        we        : in  std_logic;
        rdata     : out std_logic_vector(31 downto 0);
 
        -- Data memory port
        mem_addr  : out std_logic_vector(31 downto 0);
        mem_wdata : out std_logic_vector(31 downto 0);
        mem_we    : out std_logic;
        mem_rdata : in  std_logic_vector(31 downto 0);
 
        -- Peripheral 0: IRQ controller  (0x40000000 - 0x400000FF)
        p0_addr   : out std_logic_vector(7 downto 0);
        p0_wdata  : out std_logic_vector(31 downto 0);
        p0_we     : out std_logic;
        p0_rdata  : in  std_logic_vector(31 downto 0);
 
        -- Peripheral 1: UART            (0x40000100 - 0x400001FF)
        p1_addr   : out std_logic_vector(7 downto 0);
        p1_wdata  : out std_logic_vector(31 downto 0);
        p1_we     : out std_logic;
        p1_rdata  : in  std_logic_vector(31 downto 0);
 
        -- Peripheral 2: Timer           (0x40000200 - 0x400002FF)
        p2_addr   : out std_logic_vector(7 downto 0);
        p2_wdata  : out std_logic_vector(31 downto 0);
        p2_we     : out std_logic;
        p2_rdata  : in  std_logic_vector(31 downto 0);
 
        -- Peripheral 3: GPIO            (0x40000300 - 0x400003FF)
        p3_addr   : out std_logic_vector(7 downto 0);
        p3_wdata  : out std_logic_vector(31 downto 0);
        p3_we     : out std_logic;
        p3_rdata  : in  std_logic_vector(31 downto 0);

        -- Peripheral 4: NPU             (0x40000400 - 0x400004FF)
        p4_addr   : out std_logic_vector(7 downto 0);
        p4_wdata  : out std_logic_vector(31 downto 0);
        p4_we     : out std_logic;
        p4_rdata  : in  std_logic_vector(31 downto 0)
    );
end mmio_bus;
 
architecture Behavioral of mmio_bus is
 

    constant DMEM_BASE_HI  : std_logic_vector(15 downto 0) := x"0001";
    constant MMIO_BASE_HI  : std_logic_vector(15 downto 0) := x"4000";
 
begin
 
    process(all)
    begin
        mem_addr  <= addr;
        mem_wdata <= wdata;
        mem_we    <= '0';
 
        p0_addr  <= addr(7 downto 0); p0_wdata <= wdata; p0_we <= '0';
        p1_addr  <= addr(7 downto 0); p1_wdata <= wdata; p1_we <= '0';
        p2_addr  <= addr(7 downto 0); p2_wdata <= wdata; p2_we <= '0';
        p3_addr  <= addr(7 downto 0); p3_wdata <= wdata; p3_we <= '0';
        p4_addr  <= addr(7 downto 0); p4_wdata <= wdata; p4_we <= '0';
 
        rdata <= (others => '0');
 
        if addr(31 downto 16) = DMEM_BASE_HI then
            mem_we <= we;
            rdata  <= mem_rdata;
 
        elsif addr(31 downto 16) = MMIO_BASE_HI then
            case addr(10 downto 8) is
                when "000" =>  -- 0x40000000: IRQ controller
                    p0_we <= we;
                    rdata <= p0_rdata;
                when "001" =>  -- 0x40000100: UART
                    p1_we <= we;
                    rdata <= p1_rdata;
                when "010" =>  -- 0x40000200: Timer
                    p2_we <= we;
                    rdata <= p2_rdata;
                when "011" =>  -- 0x40000300: GPIO
                    p3_we <= we;
                    rdata <= p3_rdata;
                when "100" =>  -- 0x40000400: NPU
                    p4_we <= we;
                    rdata <= p4_rdata;
                when others =>
                    rdata <= (others => '0');
            end case;
 
        end if;
    end process;
 
end Behavioral;