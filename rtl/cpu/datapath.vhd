library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity datapath is
    port (
        clk : in std_logic;
        flagw : in std_logic_vector(3 downto 0);   -- 4-bit: N Z C V
        pcsrc, memtoreg, memwrite, alusrc, regwrite : in std_logic;
        immsrc, regsrc : in std_logic_vector(1 downto 0);
        aluco : in std_logic_vector(2 downto 0);
        instr : out std_logic_vector(31 downto 0);
        flagwm : out std_logic_vector(3 downto 0); -- 4-bit: N Z C V
        aluflags : out std_logic_vector(3 downto 0);
        -- Interrupt interface (from controlunit)
        irq_taken : in  std_logic;
        fiq_taken : in  std_logic;
        cpu_mode  : in  std_logic_vector(4 downto 0);
        npu_irq  : out std_logic;
        reg1_out : out std_logic_vector(31 downto 0);
        reg2_out : out std_logic_vector(31 downto 0);
        reg3_out : out std_logic_vector(31 downto 0)
        );
end datapath;

architecture Behavioral of datapath is
    signal pc       : std_logic_vector(31 downto 0) := (others => '0');
    signal pcnext   : std_logic_vector(31 downto 0);
    signal pcplus4f : std_logic_vector(31 downto 0);
    signal instrf   : std_logic_vector(31 downto 0);

    signal instrd   : std_logic_vector(31 downto 0) := (others => '0');
    signal pcplus8d : std_logic_vector(31 downto 0) := (others => '0');
    signal rd1, rd2 : std_logic_vector(31 downto 0);
    signal extimm   : std_logic_vector(31 downto 0);
    signal wa3d     : std_logic_vector(4 downto 0);
    signal ra1, ra2 : std_logic_vector(4 downto 0);
    signal ra1d, ra2d : std_logic_vector(4 downto 0);

    signal rd1e, rd2e, extimme, pcplus8e : std_logic_vector(31 downto 0);
    signal regwritee, memtorege, memwritee, pcsrce, alusrce : std_logic;
    signal alucoe   : std_logic_vector(2 downto 0);
    signal wa3e     : std_logic_vector(4 downto 0);
    signal flagwe   : std_logic_vector(3 downto 0);
    signal srca, srcb     : std_logic_vector(31 downto 0);
    signal aluresult      : std_logic_vector(31 downto 0);
    signal aluflags_s     : std_logic_vector(3 downto 0);
    signal ra1e, ra2e : std_logic_vector(4 downto 0);
    signal forwardae, forwardbe : std_logic_vector(1 downto 0);
    signal srcbpre : std_logic_vector(31 downto 0);
    -- Shift control - pipelined through D/E from instruction bits
    signal shift_type_e : std_logic_vector(1 downto 0);  -- instr[6:5]
    signal shift_amt_e  : std_logic_vector(4 downto 0);  -- instr[11:7]

    signal rd2m, aluresultm : std_logic_vector(31 downto 0);
    signal pcsrcm, memwritem, regwritem, memtoregm : std_logic;
    signal wa3m      : std_logic_vector(4 downto 0);
    signal readdata  : std_logic_vector(31 downto 0);
    signal aluflagsm : std_logic_vector(3 downto 0);
    signal flagwm_s  : std_logic_vector(3 downto 0) := (others => '0');

    signal readdataw, aluresultw : std_logic_vector(31 downto 0);
    signal regwritew, memtoregw  : std_logic;
    signal wa3w    : std_logic_vector(4 downto 0);
    signal resultw : std_logic_vector(31 downto 0);
    signal wdata   : std_logic_vector(31 downto 0);
    
    signal flush : std_logic;
    signal stall : std_logic;
    signal mul_stall  : std_logic;  -- stall from Wallace tree busy
    signal stall_all  : std_logic;  -- combined stall to pipeline registers

    -- Interrupt / mode signals - driven by controlunit via ports
    signal irq_lr_we_s    : std_logic;
    signal irq_lr_wdata_s : std_logic_vector(31 downto 0);
    signal fiq_lr_we_s    : std_logic;
    signal fiq_lr_wdata_s : std_logic_vector(31 downto 0);

    -- Wallace multiplier signals
    signal mul_start  : std_logic;
    signal mul_busy   : std_logic;
    signal mul_valid  : std_logic;
    signal mul_result : std_logic_vector(31 downto 0);
    signal is_mul_e   : std_logic;  -- MUL instruction in E stage
    signal signed_mode_e : std_logic;  -- signed bit from instruction

    signal cache_rdata  : std_logic_vector(31 downto 0);
    signal cache_hit    : std_logic;
    signal mem_addr_s   : std_logic_vector(31 downto 0);
    signal mem_wdata_s  : std_logic_vector(31 downto 0);
    signal mem_we_s     : std_logic;

    -- MMIO bus signals (between dcache backing store and bus)
    signal bus_rdata    : std_logic_vector(31 downto 0);

    -- Data memory (backing store, routed through MMIO bus)
    type dmem_t is array (0 to 255) of std_logic_vector(31 downto 0);
    signal dmem : dmem_t := (others => (others => '0'));
    signal dmem_addr  : std_logic_vector(31 downto 0);
    signal dmem_wdata : std_logic_vector(31 downto 0);
    signal dmem_we    : std_logic;
    signal dmem_rdata : std_logic_vector(31 downto 0);

    -- Peripheral stub read data (tie-off until real peripherals added)
    signal p0_rdata_s : std_logic_vector(31 downto 0) := (others => '0');
    signal p1_rdata_s : std_logic_vector(31 downto 0) := (others => '0');
    signal p2_rdata_s : std_logic_vector(31 downto 0) := (others => '0');
    signal p3_rdata_s : std_logic_vector(31 downto 0) := (others => '0');

    -- Peripheral stub output sinks (absorb bus outputs until peripherals exist)
    signal p0_addr_s  : std_logic_vector(7 downto 0);
    signal p0_wdata_s : std_logic_vector(31 downto 0);
    signal p0_we_s    : std_logic;
    signal p1_addr_s  : std_logic_vector(7 downto 0);
    signal p1_wdata_s : std_logic_vector(31 downto 0);
    signal p1_we_s    : std_logic;
    signal p2_addr_s  : std_logic_vector(7 downto 0);
    signal p2_wdata_s : std_logic_vector(31 downto 0);
    signal p2_we_s    : std_logic;
    signal p3_addr_s  : std_logic_vector(7 downto 0);
    signal p3_wdata_s : std_logic_vector(31 downto 0);
    signal p3_we_s    : std_logic;
    signal p4_addr_s  : std_logic_vector(7 downto 0);
    signal p4_wdata_s : std_logic_vector(31 downto 0);
    signal p4_we_s    : std_logic;
    signal p4_rdata_s : std_logic_vector(31 downto 0);
    signal npu_irq_s  : std_logic;

    -- Branch predictor signals
    signal predict_taken   : std_logic;
    signal predict_target  : std_logic_vector(31 downto 0);
    signal mispredict      : std_logic;
    signal branch_in_m     : std_logic;
    signal pcm             : std_logic_vector(31 downto 0) := (others => '0');
    signal pce             : std_logic_vector(31 downto 0) := (others => '0');

    -- --------------------------------------------------------
    -- LDM/STM sequencer
    -- --------------------------------------------------------
    type lms_state_t is (LMS_IDLE, LMS_DRAIN, LMS_ACTIVE, LMS_WB);
    signal lms_state     : lms_state_t := LMS_IDLE;
    signal lms_busy      : std_logic := '0';
    signal lms_running    : std_logic := '0';  -- sequencer owns memory/regfile
    signal lms_wb_phase  : std_logic := '0';  -- writeback final addr to base reg

    signal lms_list      : std_logic_vector(15 downto 0) := (others => '0');
    signal lms_u         : std_logic := '0';  -- U bit: 1=ascending
    signal lms_p         : std_logic := '0';  -- P bit: 1=pre-index
    signal lms_wb_en     : std_logic := '0';  -- W bit: writeback base reg
    signal lms_load      : std_logic := '0';  -- L bit: 1=LDM, 0=STM
    signal lms_breg      : std_logic_vector(3 downto 0) := (others => '0');
    signal lms_addr      : std_logic_vector(31 downto 0) := (others => '0');
    signal lms_final     : std_logic_vector(31 downto 0) := (others => '0');
    signal lms_cur_reg   : integer range 0 to 16 := 0;
    signal lms_count     : integer range 0 to 16 := 0;
    signal lms_done      : integer range 0 to 16 := 0;
    signal lms_drain_cnt : integer range 0 to 3  := 0;
    signal lms_waddr     : std_logic_vector(4 downto 0) := (others => '0');
    signal is_ldm_stm    : std_logic;

    -- Muxed datapath signals: sequencer overrides when lms_running/lms_wb_phase
    signal dc_addr_s    : std_logic_vector(31 downto 0);
    signal dc_wdata_s   : std_logic_vector(31 downto 0);
    signal dc_we_s      : std_logic;
    signal rf_raddr1_s  : std_logic_vector(4 downto 0);
    signal rf_we_s      : std_logic;
    signal rf_waddr_s   : std_logic_vector(4 downto 0);
    signal rf_wdata_s   : std_logic_vector(31 downto 0);

    -- Forwarded base register value for LDM/STM
    -- Sequencer reads this instead of raw rd1 to handle RAW hazards
    -- (e.g. ADD R5 immediately followed by STMIA R5)
    signal lms_base_fwd : std_logic_vector(31 downto 0);

    -- Count set bits in a 16-bit register list
    function count_ones(v : std_logic_vector(15 downto 0)) return integer is
        variable cnt : integer := 0;
    begin
        for i in 0 to 15 loop
            if v(i) = '1' then cnt := cnt + 1; end if;
        end loop;
        return cnt;
    end function;

    -- Find next set bit at or after 'start' (returns 16 if none)
    function next_set_bit(v : std_logic_vector(15 downto 0); start : integer)
        return integer is
    begin
        for i in 0 to 15 loop
            if i >= start and v(i) = '1' then return i; end if;
        end loop;
        return 16;
    end function;

    component regfile port(
        clk      : in std_logic;
        cpu_mode : in std_logic_vector(4 downto 0);
        raddr1 : in std_logic_vector(4 downto 0);
        rdata1 : out std_logic_vector(31 downto 0);
        raddr2 : in std_logic_vector(4 downto 0);
        rdata2 : out std_logic_vector(31 downto 0);
        r15    : in std_logic_vector(31 downto 0);
        we     : in std_logic;
        waddr  : in std_logic_vector(4 downto 0);
        wdata  : in std_logic_vector(31 downto 0);
        irq_lr_we    : in std_logic;
        irq_lr_wdata : in std_logic_vector(31 downto 0);
        fiq_lr_we    : in std_logic;
        fiq_lr_wdata : in std_logic_vector(31 downto 0);
        reg1_out : out std_logic_vector(31 downto 0);
        reg2_out : out std_logic_vector(31 downto 0);
        reg3_out : out std_logic_vector(31 downto 0));
    end component;

    component dcache port(
        clk       : in  std_logic;
        addr      : in  std_logic_vector(31 downto 0);
        wdata     : in  std_logic_vector(31 downto 0);
        we        : in  std_logic;
        rdata     : out std_logic_vector(31 downto 0);
        hit       : out std_logic;
        mem_addr  : out std_logic_vector(31 downto 0);
        mem_wdata : out std_logic_vector(31 downto 0);
        mem_we    : out std_logic;
        mem_rdata : in  std_logic_vector(31 downto 0));
    end component;

    component ALU port(
        a, b       : in std_logic_vector(31 downto 0);
        alu_ctrl   : in std_logic_vector(2 downto 0);
        shift_type : in std_logic_vector(1 downto 0);
        shift_amt  : in std_logic_vector(4 downto 0);
        result     : out std_logic_vector(31 downto 0);
        flags      : out std_logic_vector(3 downto 0));
    end component;

    component wallace_multiplier port(
        clk         : in  std_logic;
        a           : in  std_logic_vector(31 downto 0);
        b           : in  std_logic_vector(31 downto 0);
        signed_mode : in  std_logic;
        start       : in  std_logic;
        busy        : out std_logic;
        valid       : out std_logic;
        result_lo   : out std_logic_vector(31 downto 0));
    end component;

    component imem port(
        addr : in std_logic_vector(31 downto 0);
        rd   : out std_logic_vector(31 downto 0));
    end component;
    
    component hazardunit port (
        wa3m     : in std_logic_vector(4 downto 0);
        wa3w     : in std_logic_vector(4 downto 0);
        ra1e     : in std_logic_vector(4 downto 0);
        ra2e     : in std_logic_vector(4 downto 0);
        regwritem : in std_logic;
        regwritew : in std_logic;
        wa3e : in std_logic_vector(4 downto 0);
        memtorege : in std_logic;
        ra1d : in std_logic_vector(4 downto 0);
        ra2d : in std_logic_vector(4 downto 0);
        stall : out std_logic;
        forwardae : out std_logic_vector(1 downto 0);
        forwardbe : out std_logic_vector(1 downto 0));
    end component;

    component mmio_bus port(
        clk       : in  std_logic;
        addr      : in  std_logic_vector(31 downto 0);
        wdata     : in  std_logic_vector(31 downto 0);
        we        : in  std_logic;
        rdata     : out std_logic_vector(31 downto 0);
        mem_addr  : out std_logic_vector(31 downto 0);
        mem_wdata : out std_logic_vector(31 downto 0);
        mem_we    : out std_logic;
        mem_rdata : in  std_logic_vector(31 downto 0);
        p0_addr   : out std_logic_vector(7 downto 0);
        p0_wdata  : out std_logic_vector(31 downto 0);
        p0_we     : out std_logic;
        p0_rdata  : in  std_logic_vector(31 downto 0);
        p1_addr   : out std_logic_vector(7 downto 0);
        p1_wdata  : out std_logic_vector(31 downto 0);
        p1_we     : out std_logic;
        p1_rdata  : in  std_logic_vector(31 downto 0);
        p2_addr   : out std_logic_vector(7 downto 0);
        p2_wdata  : out std_logic_vector(31 downto 0);
        p2_we     : out std_logic;
        p2_rdata  : in  std_logic_vector(31 downto 0);
        p3_addr   : out std_logic_vector(7 downto 0);
        p3_wdata  : out std_logic_vector(31 downto 0);
        p3_we     : out std_logic;
        p3_rdata  : in  std_logic_vector(31 downto 0);
        p4_addr   : out std_logic_vector(7 downto 0);
        p4_wdata  : out std_logic_vector(31 downto 0);
        p4_we     : out std_logic;
        p4_rdata  : in  std_logic_vector(31 downto 0));
    end component;

    component npu_wrapper port(
        clk      : in  std_logic;
        p4_addr  : in  std_logic_vector(7 downto 0);
        p4_wdata : in  std_logic_vector(31 downto 0);
        p4_we    : in  std_logic;
        p4_rdata : out std_logic_vector(31 downto 0);
        done_irq : out std_logic);
    end component;

    component branch_predictor port(
        clk            : in  std_logic;
        pc_fetch       : in  std_logic_vector(31 downto 0);
        predict_taken  : out std_logic;
        predict_target : out std_logic_vector(31 downto 0);
        update_en      : in  std_logic;
        update_pc      : in  std_logic_vector(31 downto 0);
        actual_taken   : in  std_logic;
        actual_target  : in  std_logic_vector(31 downto 0);
        mispredict     : out std_logic);
    end component;

begin
    -- FETCH
    process(clk)
    begin
        if rising_edge(clk) then
            if (stall_all = '0') then
                pc <= pcnext;
            end if;
        end if;
    end process;

    pcplus4f <= std_logic_vector(unsigned(pc) + 4);

    -- pcnext priority (highest to lowest):
    --   1. FIQ taken     : redirect to FIQ vector 0x0000001C
    --   2. IRQ taken     : redirect to IRQ vector 0x00000018
    --   3. pcsrcm=1      : branch resolved in M
    --   4. predict_taken : speculative prediction
    --   5. default       : sequential PC+4
    pcnext <= x"0000001C"    when fiq_taken    = '1'       else
              x"00000018"    when irq_taken    = '1'       else
              aluresultm     when pcsrcm       = '1'       else
              predict_target when predict_taken = '1'      else
              pcplus4f;

    -- Flush: interrupt, confirmed branch, or misprediction recovery
    flush <= fiq_taken or irq_taken or pcsrcm or mispredict;

    -- LR save on interrupt entry: write pcplus4f to banked R14
    -- pcplus4f is the next instruction address = correct return base
    irq_lr_we_s    <= irq_taken;
    irq_lr_wdata_s <= pcplus4f;
    fiq_lr_we_s    <= fiq_taken;
    fiq_lr_wdata_s <= pcplus4f;

    -- Branch predictor instantiation
    bp : branch_predictor port map(
        clk            => clk,
        pc_fetch       => pc,
        predict_taken  => predict_taken,
        predict_target => predict_target,
        update_en      => branch_in_m,
        update_pc      => pcm,
        actual_taken   => pcsrcm,
        actual_target  => aluresultm,
        mispredict     => mispredict);

    -- branch_in_m: high whenever a branch instruction is in the M stage
    -- pcsrcm already tells us the branch was taken; but we need update_en
    -- even for not-taken branches so the counter decrements.
    -- We track whether a branch was in E by gating on pcsrce,
    -- then register it into M.
    process(clk)
    begin
        if rising_edge(clk) then
            branch_in_m <= pcsrce;   -- pcsrce=1 means a branch is in E this cycle
            pcm         <= pce;      -- PC of branch instruction at M stage
            pce         <= pc;       -- PC of instruction currently in E (approximation)
        end if;
    end process;

    im : imem port map(
        addr => pc,
        rd   => instrf);

    -- --------------------------------------------------------
    -- LDM/STM Sequencer
    -- --------------------------------------------------------
    process(clk)
        variable n      : integer;
        variable base   : unsigned(31 downto 0);
        variable next_r : integer;
    begin
        if rising_edge(clk) then
            case lms_state is

                -- ---- IDLE: watch for LDM/STM in decode ----
                when LMS_IDLE =>
                    lms_running   <= '0';
                    lms_wb_phase <= '0';
                    lms_busy     <= '0';

                    if is_ldm_stm = '1' and stall_all = '0' then
                        -- Capture instruction fields
                        lms_list  <= instrd(15 downto 0);
                        lms_u     <= instrd(23);
                        lms_p     <= instrd(24);
                        lms_wb_en <= instrd(21);
                        lms_load  <= instrd(20);
                        lms_breg  <= instrd(19 downto 16);

                        -- Count registers in list
                        n := count_ones(instrd(15 downto 0));
                        lms_count <= n;
                        lms_done  <= 0;

                        -- Base address: forwarded Rn value (handles RAW hazards)
                        base := unsigned(lms_base_fwd);

                        -- Compute start address (all modes step +4, lowest reg lowest addr)
                        -- Compute final address for optional writeback
                        if instrd(23) = '1' then          -- U=1: ascending
                            lms_final <= std_logic_vector(base + to_unsigned(n*4, 32));
                            if instrd(24) = '0' then       -- IA: start at base
                                lms_addr <= std_logic_vector(base);
                            else                           -- IB: start at base+4
                                lms_addr <= std_logic_vector(base + 4);
                            end if;
                        else                               -- U=0: descending
                            lms_final <= std_logic_vector(base - to_unsigned(n*4, 32));
                            if instrd(24) = '0' then       -- DA: start = base-(N-1)*4
                                if n > 1 then
                                    lms_addr <= std_logic_vector(
                                        base - to_unsigned((n-1)*4, 32));
                                else
                                    lms_addr <= std_logic_vector(base);
                                end if;
                            else                           -- DB: start = base-N*4
                                lms_addr <= std_logic_vector(
                                    base - to_unsigned(n*4, 32));
                            end if;
                        end if;

                        lms_busy      <= '1';
                        lms_drain_cnt <= 0;
                        lms_state     <= LMS_DRAIN;
                    end if;

                -- ---- DRAIN: wait 3 cycles for pipeline to clear ----
                when LMS_DRAIN =>
                    if lms_drain_cnt = 2 then
                        -- Pipeline empty - find first active register and start
                        next_r      := next_set_bit(lms_list, 0);
                        lms_cur_reg <= next_r;
                        lms_waddr   <= '0' & std_logic_vector(
                                            to_unsigned(next_r, 4));
                        lms_running  <= '1';
                        lms_state   <= LMS_ACTIVE;
                    else
                        lms_drain_cnt <= lms_drain_cnt + 1;
                    end if;

                -- ---- ACTIVE: one memory transfer per cycle ----
                when LMS_ACTIVE =>
                    if lms_done = lms_count then
                        -- All registers transferred
                        lms_running <= '0';
                        if lms_wb_en = '1' then
                            lms_wb_phase <= '1';  -- write final addr to base reg
                            lms_state    <= LMS_WB;
                        else
                            lms_busy  <= '0';
                            lms_state <= LMS_IDLE;
                        end if;
                    else
                        -- Current transfer is driven combinationally this cycle.
                        -- Advance: address +4, find next register bit.
                        lms_addr <= std_logic_vector(unsigned(lms_addr) + 4);
                        lms_done <= lms_done + 1;

                        if lms_cur_reg < 15 then
                            next_r := next_set_bit(lms_list, lms_cur_reg + 1);
                        else
                            next_r := 16;
                        end if;
                        lms_cur_reg <= next_r;
                        if next_r <= 15 then
                            lms_waddr <= '0' & std_logic_vector(
                                              to_unsigned(next_r, 4));
                        end if;
                    end if;

                -- ---- WB: write final address back to base register ----
                when LMS_WB =>
                    -- rf_wdata_s = lms_final, rf_waddr_s = lms_breg driven by mux
                    -- combinational regfile write happens this cycle
                    lms_wb_phase <= '0';
                    lms_busy     <= '0';
                    lms_state    <= LMS_IDLE;

            end case;
        end if;
    end process;
    
    -- F/D PIPELINE REGISTER
    -- Uses stall_all (not just hazard stall) so LDM/STM and MUL stalls
    -- also freeze fetch/decode, preventing instruction skipping
    process(clk)
    begin
        if rising_edge(clk) then
            if (stall_all = '1') then
                null;
            elsif (flush = '1') then
                pcplus8d <= (others => '0');
                instrd <= (others => '0');    
            else
                pcplus8d <= pcplus4f;
                instrd   <= instrf;    
            end if;    
        end if;
    end process;

    -- DECODE
    instr <= instrd;

    ra1  <= "01111" when regsrc(0) = '1' else '0' & instrd(19 downto 16);
    ra2  <= '0' & instrd(15 downto 12) when regsrc(1) = '1' else '0' & instrd(3 downto 0);
    wa3d <= '0' & instrd(15 downto 12);
    ra1d <= ra1;
    ra2d <= ra2;

    rf : regfile port map(
        clk      => clk,
        cpu_mode => cpu_mode,          -- from controlunit via top
        raddr1   => rf_raddr1_s,
        rdata1   => rd1,
        raddr2   => ra2,
        rdata2   => rd2,
        r15      => pcplus8d,
        we       => rf_we_s,
        waddr    => rf_waddr_s,
        wdata    => rf_wdata_s,
        irq_lr_we    => irq_lr_we_s,
        irq_lr_wdata => irq_lr_wdata_s,
        fiq_lr_we    => fiq_lr_we_s,
        fiq_lr_wdata => fiq_lr_wdata_s,
        reg1_out => reg1_out,
        reg2_out => reg2_out,
        reg3_out => reg3_out);
    
    hu : hazardunit port map(
        wa3m => wa3m,
        wa3w => wa3w,
        regwritem => regwritem,
        regwritew => regwritew,
        ra1e => ra1e,
        ra2e => ra2e,
        forwardae => forwardae,
        forwardbe => forwardbe,
        wa3e => wa3e,
        memtorege => memtorege,
        ra1d => ra1d,
        ra2d => ra2d,
        stall => stall
        );    

    process(all)
    begin
        case immsrc is
            when "00" =>
                extimm <= x"000000" & instrd(7 downto 0);
            when "01" =>
                extimm <= x"000" & "00000000" & instrd(11 downto 0);
            when "10" =>
                extimm <= std_logic_vector(resize(signed(instrd(23 downto 0)), 32));
            when "11" =>
                extimm <= (others => '0');
            when others =>
                extimm <= (others => '0');
        end case;
    end process;

    -- D/E PIPELINE REGISTER
    process(clk)
    begin
        if rising_edge(clk) then
            if (stall_all = '1') then 
                rd1e      <= (others => '0');
                rd2e      <= (others => '0');
                extimme   <= (others => '0');
                wa3e      <= (others => '0');
                pcplus8e  <= (others => '0');
                regwritee <= '0';
                memtorege <= '0';
                memwritee <= '0';
                pcsrce    <= '0';
                alusrce   <= '0';
                alucoe    <= (others => '0');
                flagwe    <= (others => '0');
                ra1e <= (others => '0');
                ra2e <= (others => '0');
                shift_type_e <= (others => '0');
                shift_amt_e  <= (others => '0');
            elsif (flush = '1') then
                rd1e      <= (others => '0');
                rd2e      <= (others => '0');
                extimme   <= (others => '0');
                wa3e      <= (others => '0');
                pcplus8e  <= (others => '0');
                regwritee <= '0';
                memtorege <= '0';
                memwritee <= '0';
                pcsrce    <= '0';
                alusrce   <= '0';
                alucoe    <= (others => '0');
                flagwe    <= (others => '0');
                ra1e <= (others => '0');
                ra2e <= (others => '0');
                shift_type_e <= (others => '0');
                shift_amt_e  <= (others => '0');
            else
                rd1e      <= rd1;
                rd2e      <= rd2;
                extimme   <= extimm;
                wa3e      <= wa3d;
                pcplus8e  <= pcplus8d;
                regwritee <= regwrite;
                memtorege <= memtoreg;
                memwritee <= memwrite;
                pcsrce    <= pcsrc;
                alusrce   <= alusrc;
                alucoe    <= aluco;
                flagwe    <= flagw;
                ra1e <= ra1;
                ra2e <= ra2;
                shift_type_e <= instrd(6 downto 5);   -- barrel shifter type
                shift_amt_e  <= instrd(11 downto 7);  -- barrel shifter amount
            end if;
        end if;            
    end process;

    -- EXECUTE
    srca <= rd1e when (forwardae = "00") else 
            resultw when (forwardae = "01") else 
            aluresultm;
    srcbpre <= rd2e when (forwardbe = "00") else 
               resultw when (forwardbe = "01") else 
               aluresultm;
    
    srcb <= extimme when alusrce = '1' else srcbpre;

    -- MUL detection: alucoe = "101" means MUL is in E stage
    is_mul_e     <= '1' when alucoe = "101" else '0';
    mul_start    <= is_mul_e;
    -- Signed mode: instruction bit 20 selects signed/unsigned
    -- (reuse funct bit 0 - already in the pipeline via instrd)
    signed_mode_e <= instrd(20);

    -- Combined stall: load-use hazard OR multiplier busy OR LDM/STM active
    mul_stall <= mul_busy;
    stall_all <= stall or mul_stall or lms_busy;

    -- LDM/STM detection: instr[27:25] = "100"
    is_ldm_stm <= '1' when instrd(27 downto 25) = "100" else '0';

    -- Forward base register (Rn) for LDM/STM decode-stage read.
    -- Checks E, M, W stages in priority order - same logic as execute forwarding.
    -- Needed when the instruction immediately before LDM/STM writes Rn.
    lms_base_fwd <= aluresult  when (regwritee = '1' and
                                     wa3e = '0' & instrd(19 downto 16)) else
                    aluresultm when (regwritem = '1' and
                                     wa3m = '0' & instrd(19 downto 16)) else
                    resultw    when (regwritew = '1' and
                                     wa3w = '0' & instrd(19 downto 16)) else
                    rd1;

    -- Dcache mux: sequencer takes over during ACTIVE, else normal pipeline
    dc_addr_s  <= lms_addr       when lms_running = '1' else aluresultm;
    dc_wdata_s <= rd1            when lms_running = '1' else rd2m;
    dc_we_s    <= (not lms_load) when lms_running = '1' else memwritem;

    -- Register file mux: sequencer takes over during ACTIVE and WB
    rf_raddr1_s <= lms_waddr    when lms_running   = '1' else ra1;
    rf_we_s     <= '1'          when lms_wb_phase = '1' else
                   lms_load     when lms_running   = '1' else
                   regwritew;
    rf_waddr_s  <= '0' & lms_breg when lms_wb_phase = '1' else
                   lms_waddr    when lms_running   = '1' else
                   wa3w;
    rf_wdata_s  <= lms_final    when lms_wb_phase = '1' else
                   cache_rdata  when lms_running   = '1' else
                   wdata;

    alu_inst : ALU port map(
        a          => srca,
        b          => srcb,
        alu_ctrl   => alucoe,
        shift_type => shift_type_e,
        shift_amt  => shift_amt_e,
        result     => aluresult,
        flags      => aluflags_s);

    mul_inst : wallace_multiplier port map(
        clk         => clk,
        a           => srca,
        b           => srcbpre,   -- always register operand for MUL
        signed_mode => signed_mode_e,
        start       => mul_start,
        busy        => mul_busy,
        valid       => mul_valid,
        result_lo   => mul_result);

    -- E/M PIPELINE REGISTER
    -- Uses stall_all to freeze on both load-use and MUL stalls
    process(clk)
    begin
        if rising_edge(clk) then
            if flush = '1' then
                aluresultm  <= (others => '0');
                rd2m        <= (others => '0');
                pcsrcm      <= '0';
                memwritem   <= '0';
                memtoregm   <= '0';
                regwritem   <= '0';
                wa3m        <= (others => '0');
                aluflagsm   <= (others => '0');
                flagwm_s    <= (others => '0');
            else
                if mul_valid = '1' then
                    aluresultm <= mul_result;
                else
                    aluresultm <= aluresult;
                end if;
    
                rd2m       <= srcbpre;
                pcsrcm     <= pcsrce;
                memwritem  <= memwritee;
                memtoregm  <= memtorege;
                regwritem  <= regwritee;
                wa3m       <= wa3e;
                aluflagsm  <= aluflags_s;
                flagwm_s   <= flagwe;
            end if;
        end if;
    end process;

    aluflags <= aluflagsm;
    flagwm   <= flagwm_s;

    dc : dcache port map(
        clk       => clk,
        addr      => dc_addr_s,    -- muxed: LDM/STM addr or normal aluresultm
        wdata     => dc_wdata_s,   -- muxed: STM reg value or normal rd2m
        we        => dc_we_s,      -- muxed: STM write or normal memwritem
        rdata     => cache_rdata,
        hit       => cache_hit,
        mem_addr  => mem_addr_s,
        mem_wdata => mem_wdata_s,
        mem_we    => mem_we_s,
        mem_rdata => bus_rdata);

    -- MMIO bus: routes cache misses to dmem or peripheral registers
    mbus : mmio_bus port map(
        clk       => clk,
        addr      => mem_addr_s,
        wdata     => mem_wdata_s,
        we        => mem_we_s,
        rdata     => bus_rdata,
        mem_addr  => dmem_addr,
        mem_wdata => dmem_wdata,
        mem_we    => dmem_we,
        mem_rdata => dmem_rdata,
        p0_addr   => p0_addr_s,  p0_wdata => p0_wdata_s,  p0_we => p0_we_s,  p0_rdata => p0_rdata_s,
        p1_addr   => p1_addr_s,  p1_wdata => p1_wdata_s,  p1_we => p1_we_s,  p1_rdata => p1_rdata_s,
        p2_addr   => p2_addr_s,  p2_wdata => p2_wdata_s,  p2_we => p2_we_s,  p2_rdata => p2_rdata_s,
        p3_addr   => p3_addr_s,  p3_wdata => p3_wdata_s,  p3_we => p3_we_s,  p3_rdata => p3_rdata_s,
        p4_addr   => p4_addr_s,  p4_wdata => p4_wdata_s,  p4_we => p4_we_s,  p4_rdata => p4_rdata_s);

    -- NPU wrapper: bridges P4 MMIO port to accelerator_top
    npu : npu_wrapper port map(
        clk      => clk,
        p4_addr  => p4_addr_s,
        p4_wdata => p4_wdata_s,
        p4_we    => p4_we_s,
        p4_rdata => p4_rdata_s,
        done_irq => npu_irq_s);

    npu_irq <= npu_irq_s;

    -- Backing data memory
    process(clk)
    begin
        if rising_edge(clk) then
            if dmem_we = '1' then
                dmem(to_integer(unsigned(dmem_addr(9 downto 2)))) <= dmem_wdata;
            end if;
        end if;
    end process;
    dmem_rdata <= dmem(to_integer(unsigned(dmem_addr(9 downto 2))));

    readdata <= cache_rdata;

    -- M/W PIPELINE REGISTER
    process(clk)
    begin
        if rising_edge(clk) then
            readdataw  <= readdata;
            aluresultw <= aluresultm;
            regwritew  <= regwritem;
            memtoregw  <= memtoregm;
            wa3w       <= wa3m;
        end if;
    end process;

    -- WRITEBACK
    resultw <= readdataw when memtoregw = '1' else aluresultw;
    wdata   <= resultw;

end Behavioral;