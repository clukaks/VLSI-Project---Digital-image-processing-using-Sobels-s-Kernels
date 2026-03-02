--taster realizovan po ugledu na edge detector sa vezbi sa debalansiranjem

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity btn_control is
    generic (
        TIMER_MAX : integer := 1000000 --konstanta koja nam sluzi za debalansiranje
    );                                 --izabrana je bas ova, da bi vreme "provere tastera" bilo 10ms, za clk od 100MHz
    port (
        clk   : in  std_logic;
        reset : in  std_logic;
        button : in  std_logic;       --signal pritiska dugmeta
        button_pulse : out std_logic  --signal koji generisemo na izlazu, nakon sto je odredjeno da je pritisak tastera validan
    );
end entity btn_control;

architecture Behavioral_btn_control of btn_control is

    type State_t is ( st_idle, st_count, st_stable, st_edge, st_wait_release );
    signal state_reg, next_state : State_t;
    signal timer : integer range 0 to TIMER_MAX := TIMER_MAX;
    
begin

    NEXT_STATE_LOGIC: process(state_reg, button, timer) is
    begin
        next_state <= state_reg;

        case state_reg is

            when st_idle =>
                if button = '1' then
                    next_state <= st_count;
                end if;

            when st_count =>
                if button = '0' then
                    next_state <= st_idle;
                elsif timer = 0 then
                    next_state <= st_stable;
                end if;

            when st_stable =>
                if button = '1' then
                    next_state <= st_edge;
                else
                    next_state <= st_idle;
                end if;

            when st_edge =>
                next_state <= st_wait_release;

            when st_wait_release =>   --nakon priteiska tastera odlazimo u ovo stanje, cekamo da prodje 1000000 taktova
                if button = '0' then  --odnosno 10ms i nakon toga, detektujemo pritisak tastera
                    next_state <= st_idle;
                end if;

        end case;
    end process NEXT_STATE_LOGIC;

    OUTPUT_LOGIC: process(state_reg) is
    begin
        if state_reg = st_edge then
            button_pulse <= '1';
        else
            button_pulse <= '0';
        end if;
    end process OUTPUT_LOGIC;

--proces u kome vrsimo promenu stanja i tajmera, koji nam sluzi za debalansiranje
    STATE_TRANSITION_AND_TIMER: process(clk) is
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state_reg <= st_idle;
                timer     <= TIMER_MAX;
            else
                state_reg <= next_state;

                case next_state is
                    when st_idle =>
                        timer <= TIMER_MAX;

                    when st_count =>
                        timer <= timer - 1;

                    when others =>
                        timer <= TIMER_MAX;
                end case;
            end if;
        end if;
    end process STATE_TRANSITION_AND_TIMER;

end architecture;
