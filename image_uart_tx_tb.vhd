--ovo je kontroler za nasu UART komponentu, koji sluzi da upravlja njenim radom. 
--On uzima piksele iz memorije i posto je FSM uzima neophodne piksele i salje ih na serijsku komunikaciju

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity image_uart_tx is
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        start_uart : in  std_logic;
        -- RAM interfejs
        ram_data   : in  std_logic_vector(7 downto 0);
        ram_addr   : out std_logic_vector(15 downto 0);
        -- UART serial output
        tx         : out std_logic;
        done       : out std_logic
    );
end entity image_uart_tx;

architecture Behavioral_image_uart_tx of image_uart_tx is

    type State_t is ( idle, wait_ready, send_byte, wait_busy, finish );
    signal state_reg, next_state : State_t;
    signal addr_cnt : unsigned(15 downto 0) := (others => '0');
    
    --signali nephodni za nasu masinu stanja
    signal tx_busy_i   : std_logic;
    signal tx_dvalid_i : std_logic := '0';
    signal tx_data_i   : std_logic_vector(7 downto 0) := (others => '0');

begin
    ram_addr <= std_logic_vector(addr_cnt);

    --instanciranje date UART komponente
    UART_TX_I : entity work.uart_tx
        generic map (
            CLK_FREQ => 100,   -- MHz
            SER_FREQ => 115200-- (ovo je za tb 25000000) Baud Rate koji je podesen na osnovu preporucenog iz teksta projekta
        )
        port map (
            clk => clk,
            rst => reset,
            tx  => tx,
            par_en => '0',
            tx_dvalid => tx_dvalid_i,
            tx_data => tx_data_i,
            tx_busy => tx_busy_i
        );
        
    NEXT_STATE_LOGIC: process(state_reg, start_uart, tx_busy_i, addr_cnt) is
    begin
        next_state <= state_reg;

        case state_reg is

            when idle => --u ovom stanju cekamo signal od control_modula da krenemo sa slanjem
                if start_uart = '1' then
                    next_state <= wait_ready;
                end if;

            when wait_ready =>
                --Cekamo da UART bude slobodan pre slanja, tx_busy treba da nam bude 0
                if tx_busy_i = '0' then
                    next_state <= send_byte;
                end if;

          --stannje koje UARTu daje znak da krene, i kada se tx_busy promeni na 1, tek tada idemo dalje
            when send_byte => 
                if tx_busy_i = '1' then
                    next_state <= wait_busy;
                else
                    next_state <= send_byte; --Ostajemo ovde i drzimo dvalid na '1'
                end if;

          --stanje u kojem uvecavamo adresu, za sta je logika u drugom procesu realizovana
            when wait_busy =>
                --Vrsimo proveru da li smo dosli do poslednje adrese u memoriji, preko brojaca
                if tx_busy_i = '1' then
                    if addr_cnt = x"FFFF" then
                        next_state <= finish;
                    else
                        next_state <= wait_ready; -- Vracamo se i cekamo da UART zavrsi slanje starog piksela, da tx_busy
                                                  -- padne na nulu, i da mozemo da saljemo drugi piksel
                    end if;
                end if;

            when finish =>
                next_state <= idle;

        end case;
    end process NEXT_STATE_LOGIC;
    
    
    STATE_TRANSITION: process(clk) is
        begin
            if rising_edge(clk) then
                if reset = '1' then
                    state_reg <= idle;
                else
                    state_reg <= next_state;
                end if;
            end if;
     end process STATE_TRANSITION;
    
    
    OUTPUT_LOGIC: process(clk) is
    begin
        if rising_edge(clk) then
            if reset = '1' then
                addr_cnt    <= (others => '0');
                tx_dvalid_i <= '0';
                tx_data_i <= (others => '0');
                done  <= '0';

            else
                tx_dvalid_i <= '0';
                done <= '0';

                case state_reg is

                    when idle =>
                        addr_cnt <= (others => '0');

                    when wait_ready =>
                        null;

                    when send_byte =>
                        tx_data_i <= ram_data;
                        tx_dvalid_i <= '1'; -- Ovo ostaje '1' sve dok smo u send_byte stanju

                    when wait_busy => --stanje u kojem uvecamo adresu, kako bi se spremili za slanje sledeceg piksela
                        if tx_busy_i = '1' then
                            addr_cnt <= addr_cnt + 1;
                        end if;

                    when finish =>
                        done <= '1';

                end case;
            end if;
        end if;
    end process OUTPUT_LOGIC;

end architecture Behavioral_image_uart_tx;