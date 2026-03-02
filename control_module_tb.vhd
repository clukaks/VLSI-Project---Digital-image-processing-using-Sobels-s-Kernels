--glavni modul za kontrou rada naseg dizajna, objedinjuje sve komponente i uz pomoc jedne masine stanja
--realizuje neophodnu komunikaciju, citanje RAMa, obradu slike, upis u RAM i serijsku komunikaciju za prikaz slike

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity control_module is
    port (
        clk      : in  std_logic; -- OVO JE 125 MHz SA PLOCE
        reset    : in  std_logic; 
        button   : in  std_logic; 
        uart_tx  : out std_logic;  
        led      : out std_logic_vector(2 downto 1)
    );
end entity control_module;

architecture Behavioral_control_module of control_module is

    --komponenta clok wizard, za input clock od 125MHz daje output od 100MHz
    component clk_wiz_0
        port (
            clk_in1  : in  std_logic;
            clk_out1 : out std_logic
        );
    end component;
    
    signal clk_100mhz : std_logic;
    --stanja nase masine stanja
    type state_t is (IDLE, RUN_GRAD, SEND_UART, DONE);

    signal current_state, next_state : state_t := IDLE;
    signal btn_pulse : std_logic;
    
    -- Signali iz grad_mag
    signal gm_start : std_logic := '0';
    signal gm_done  : std_logic;       
    signal gm_wea   : std_logic;
    signal gm_addra : std_logic_vector(15 downto 0); 
    signal gm_dina  : std_logic_vector(7 downto 0);
    signal gm_addrb : std_logic_vector(15 downto 0); 
    signal gm_enb   : std_logic;
      
    --Signali iz image_uart_tx
    signal uart_start : std_logic := '0';
    signal uart_done : std_logic;
    signal uart_addr : std_logic_vector(15 downto 0); 
      
    --"MUX" Signali za RAM, sluze da prilikom razlicitih stanja, tacno znamo sta se radi sa RAMom
    signal ram_addrb_mux : std_logic_vector(15 downto 0); 
    signal ram_doutb : std_logic_vector(7 downto 0);  
    
begin

    led(1) <= '1'; --Svetli iznad BTN1 (start)
    led(2) <= '1'; --Svetli iznad BTN2 (reset)
    clk_gen_inst : clk_wiz_0
        port map (
            clk_in1  => clk, -- Ulaz sa clock 125 MHz
            clk_out1 => clk_100mhz --izlazni clock, nas dizajn maksimalno radi na 113MHz, pa smo se odlucili na 100MHz
--    clk_100mhz <= clk; --ovo je za tb, clk wizard treba da bude zakomentarisan
        );
    
    --instanciranje tastera
    BTN: entity work.btn_control
        generic map (
            TIMER_MAX => 1000000 --za tb prebaciti u 10 
        )
        port map (
            clk => clk_100mhz,
            reset => reset,
            button => button,
            button_pulse => btn_pulse
        );
        
    --modul za racunanje magnitude gradijenta
    GRAD: entity work.grad_mag
        port map (
            clk        => clk_100mhz,
            reset      => reset,
            grad_start => gm_start,
            grad_done  => gm_done,    
            ram_enb    => gm_enb,
            ram_addrb  => gm_addrb,
            ram_doutb  => ram_doutb,  
            ram_wea    => gm_wea,
            ram_addra  => gm_addra,
            ram_dina   => gm_dina,
          
            wr_pulse   => open, --ovo su signali koje smo koristili za Debug, 
                                --prilikom druge faze, da ne bi svaki put kad hocemo da proverimo sliku morali da spustamo na plocicu
            wr_data    => open
        );
    
    --UART modul za slanje slike, realizovan je preko datog UARTa uz tekst projekta
    UART_IMG: entity work.image_uart_tx
        port map (
            clk => clk_100mhz,
            reset => reset,
            start_uart => uart_start,
            ram_data   => ram_doutb, 
            ram_addr => uart_addr, 
            tx       => uart_tx,
            done     => uart_done
        );
    
    --nas RAM za citanje i za upis
    RAM: entity work.im_ram
        port map (
            clka   => clk_100mhz,
            wea    => gm_wea,    
            addra  => gm_addra,
            dina   => gm_dina,
            addrb  => ram_addrb_mux,
            doutb  => ram_doutb,
            enb    => '1',      
            rstb   => '0',
            regceb => '0'       
        );
    
    STATE_TRANSITION: process(clk_100mhz) is
    begin
        if rising_edge(clk_100mhz) then
            if reset='1' then
                current_state <= IDLE;
            else
                current_state <= next_state;
            end if;
        end if;
    end process STATE_TRANSITION;
    
    NEXT_STATE_AND_SIGNAL_LOGIC: process(current_state, btn_pulse, gm_done, uart_done, gm_addrb, uart_addr) is
    begin
        next_state <= current_state;
        gm_start   <= '0';
        uart_start <= '0';
        ram_addrb_mux <= (others => '0');

        case current_state is
    
            when IDLE =>
                ram_addrb_mux <= (others => '0'); --nema citanja iz RAMa u IDLE stanju
                if btn_pulse='1' then
                    gm_start <= '1';    
                    next_state <= RUN_GRAD;
                end if;
    
            when RUN_GRAD =>
                ram_addrb_mux <= gm_addrb; -- citanje slike iz RAMa za obradu
                if gm_done = '1' then
                    uart_start <= '1'; 
                    next_state <= SEND_UART;
                end if;
    
            when SEND_UART =>
                ram_addrb_mux <= uart_addr; -- UART cita iz RAM-a
                if uart_done = '1' then
                    next_state <= IDLE;     
                end if;
    
            when others =>
                next_state <= IDLE;
    
        end case;
    end process NEXT_STATE_AND_SIGNAL_LOGIC;
    
end architecture;