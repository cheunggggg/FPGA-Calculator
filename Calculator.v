`timescale 1ns / 1ps

// display controller for 7seg conversion
module DisplayController(
    input [3:0] DispVal,
    output reg [6:0] segOut,
    output reg [6:0] SSD
);
    // convert val to 7seg pattern
    always @(DispVal) begin
        case(DispVal)
            4'd0: begin 
                segOut = 7'b1000000; // "0" for main disp (active low)
                SSD = 7'b0111111;    // "0" for PmodSSD (active high)
            end
            4'd1: begin 
                segOut = 7'b1111001; // "1" for main disp
                SSD = 7'b0000110;    // "1" for PmodSSD
            end
            4'd2: begin 
                segOut = 7'b0100100; // "2" for main disp
                SSD = 7'b1011011;    // "2" for PmodSSD
            end
            4'd3: begin 
                segOut = 7'b0110000; // "3" for main disp
                SSD = 7'b1001111;    // "3" for PmodSSD
            end
            4'd4: begin 
                segOut = 7'b0011001; // "4" for main disp
                SSD = 7'b1100110;    // "4" for PmodSSD
            end
            4'd5: begin 
                segOut = 7'b0010010; // "5" for main disp
                SSD = 7'b1101101;    // "5" for PmodSSD
            end
            4'd6: begin 
                segOut = 7'b0000010; // "6" for main disp
                SSD = 7'b1111101;    // "6" for PmodSSD
            end
            4'd7: begin 
                segOut = 7'b1111000; // "7" for main disp
                SSD = 7'b0000111;    // "7" for PmodSSD
            end
            4'd8: begin 
                segOut = 7'b0000000; // "8" for main disp
                SSD = 7'b1111111;    // "8" for PmodSSD
            end
            4'd9: begin 
                segOut = 7'b0010000; // "9" for main disp
                SSD = 7'b1101111;    // "9" for PmodSSD
            end
            default: begin 
                segOut = 7'b1111111; // blank for main disp
                SSD = 7'b0000000;    // blank for pmodssd
            end
        endcase
    end
endmodule

// pmod ssd display ctrl
module DisplaySSD(
    input clk,
    input [3:0] digit5,  // 10000s digit
    input [3:0] digit6,  // 100000s digit
    output reg [6:0] SSD, // 7seg signals
    output reg CAT       // common cath/anod ctrl
);
    reg [3:0] digitVal;
    wire [6:0] segOut;   // not used but needed for dispcntrl
    wire [6:0] ssdOut;   // output from dispcntrl
    
    // use display ctrl to cvt digit to segs
    DisplayController dec(
        .DispVal(digitVal),
        .segOut(segOut),
        .SSD(ssdOut)
    );
    
    // counter for muxing the 2 digits
    reg refresh_counter = 0;
    
    // digit disp mux - alternates btwn digit5/6
    always @(posedge clk) begin
        // slow down the muxing
        refresh_counter <= refresh_counter + 1;
        
        if (refresh_counter == 0) begin
            if (CAT == 1'b0) begin
                // currently showing dig5, switch to dig6
                digitVal <= digit6;
                CAT <= 1'b1;
            end else begin
                // currently showing dig6, switch to dig5
                digitVal <= digit5;
                CAT <= 1'b0;
            end
            
            // update ssd out
            SSD <= ssdOut;
        end
    end
    
    // init state
    initial begin
        CAT = 1'b0;
        digitVal = 4'd0;
    end
endmodule

// main calc module
module Calculator(
    input wire [15:0] sw,      // 16 switches
    input wire btnL,           // add btn (T18)
    input wire btnR,           // sub btn (W19)
    input wire btnU,           // mult btn (T17)
    input wire btnD,           // div btn (U17)
    input wire btnC,           // equals btn (U18)
    input wire [3:0] btn_ext,  // ext btns on JB (BTN0-3)
    input wire clk,            // clk input
    output reg [6:0] seg,      // 7seg display segs for onboard disp
    output reg [3:0] an,       // 7seg display anodes for onboard disp (digit sel)
    output wire [6:0] SSD,     // 7seg sigs for Pmod SSD (split across hdrs)
    output wire CAT,           // common cath ctrl for Pmod SSD
    output reg [15:0] led      // leds for debug (LD15 for neg result)
);

    // consts for disp refresh
    localparam REFRESH_RATE = 500;       // Hz
    localparam CLK_FREQ = 100000000;     // 100 MHz
    localparam COUNT_MAX = CLK_FREQ / REFRESH_RATE / 4; // 4 digits for onboard disp
    
    // sigs for input sampling & btn debouncing
    reg [19:0] btn_debounce_counter = 0;
    reg btnL_debounced = 0, btnR_debounced = 0, btnU_debounced = 0, btnD_debounced = 0, btnC_debounced = 0;
    reg btnL_prev = 0, btnR_prev = 0, btnU_prev = 0, btnD_prev = 0, btnC_prev = 0;
    
    // ext btns debouncing
    reg [3:0] btn_ext_debounced = 0;
    reg [3:0] btn_ext_prev = 0;
    
    // sigs for ops and results
    wire [6:0] num1;     // 6bits + sign
    wire [6:0] num2;     // 6bits + sign
    reg [3:0] operation = 0; // 0:none, 1:add, 2:sub, 3:mult, 4:div, 5:mod, 6:exp, 7:neg
    reg signed [31:0] result = 0;        // expanded to 32bits for big nums
    reg signed [31:0] display_value = 0; // expanded to 32bits for big nums
    
    // pwr calc intermediate vals
    reg [31:0] power_result = 1;         // expanded to 32bits for big results
    reg [5:0] power_counter = 0;
    reg power_calculating = 0;
    
    // sigs for disp ctrl
    reg [1:0] digit_select = 0;  // for 4 onboard digits
    reg [31:0] refresh_counter = 0;
    
    // prep input nums w/ sign
    // 1st num: sw0-sw5 w/ sw12 as sign
    assign num1 = {sw[12], sw[5:0]};
    
    // 2nd num: sw6-sw11 w/ sw13 as sign
    assign num2 = {sw[13], sw[11:6]};
    
    // init led out
    initial led = 16'b0;
    
    // extract digits for disp
    reg [31:0] abs_value;
    reg [3:0] digit1, digit2, digit3, digit4, digit5, digit6;
    
    // instantiate pmodssd disp ctrl
    DisplaySSD pmod_display(
        .clk(clk),
        .digit5(digit5),
        .digit6(digit6),
        .SSD(SSD),
        .CAT(CAT)
    );
    
    // btn handling and op execution
    always @(posedge clk) begin
        // btn debouncing cntr
        btn_debounce_counter <= btn_debounce_counter + 1;
        
        // sample btn states at slower rate for debouncing
        if (btn_debounce_counter == 0) begin
            btnL_debounced <= btnL;
            btnR_debounced <= btnR;
            btnU_debounced <= btnU;
            btnD_debounced <= btnD;
            btnC_debounced <= btnC;
            btn_ext_debounced <= btn_ext;
        end
        
        // btn edge detection
        btnL_prev <= btnL_debounced;
        btnR_prev <= btnR_debounced;
        btnU_prev <= btnU_debounced;
        btnD_prev <= btnD_debounced;
        btnC_prev <= btnC_debounced;
        btn_ext_prev <= btn_ext_debounced;
        
        // btn pressed detection (rising edge)
        if (btnL_debounced && !btnL_prev)
            operation <= 1; // add
        else if (btnR_debounced && !btnR_prev)
            operation <= 2; // sub
        else if (btnU_debounced && !btnU_prev)
            operation <= 3; // mult
        else if (btnD_debounced && !btnD_prev)
            operation <= 4; // div
        else if (btn_ext_debounced[0] && !btn_ext_prev[0])
            operation <= 5; // mod
        else if (btn_ext_debounced[1] && !btn_ext_prev[1])
            operation <= 6; // exp (pwr)
        else if (btn_ext_debounced[2] && !btn_ext_prev[2])
            operation <= 7; // neg
            
        // clr btn pressed
        if (btn_ext_debounced[3] && !btn_ext_prev[3]) begin
            display_value <= 0;
            result <= 0;
            operation <= 0;
            led <= 16'b0;
        end
        
        // exp calc state machine
        if (power_calculating) begin
            if (power_counter < $signed(num2)) begin
                power_result <= power_result * $signed(num1);
                power_counter <= power_counter + 1;
                
                // check for overflow
                if (power_result > 999999) begin
                    power_result <= 999999; // limit to 6 digits
                    power_calculating <= 0;
                end
            end
            else begin
                power_calculating <= 0;
                result <= power_result;
                display_value <= power_result;
                
                // update LED15 for neg result
                led <= {power_result[31], 15'b0};
            end
        end
        
        // equals btn pressed - do calc
        if (btnC_debounced && !btnC_prev) begin
            case (operation)
                1: begin // add
                    result <= $signed(num1) + $signed(num2);
                    display_value <= $signed(num1) + $signed(num2);
                    led <= {($signed(num1) + $signed(num2)) < 0 ? 1'b1 : 1'b0, 15'b0};
                end
                2: begin // sub
                    result <= $signed(num1) - $signed(num2);
                    display_value <= $signed(num1) - $signed(num2);
                    led <= {($signed(num1) - $signed(num2)) < 0 ? 1'b1 : 1'b0, 15'b0};
                end
                3: begin // mult
                    result <= $signed(num1) * $signed(num2);
                    display_value <= $signed(num1) * $signed(num2);
                    led <= {($signed(num1) * $signed(num2)) < 0 ? 1'b1 : 1'b0, 15'b0};
                end
                4: begin // div
                    if ($signed(num2) == 0) begin
                        // disp err code for div by 0
                        result <= 9999; // err code
                        display_value <= 9999;
                        led <= 16'b0;
                    end
                    else begin
                        result <= $signed(num1) / $signed(num2);
                        display_value <= $signed(num1) / $signed(num2);
                        led <= {($signed(num1) / $signed(num2)) < 0 ? 1'b1 : 1'b0, 15'b0};
                    end
                end
                5: begin // mod
                    if ($signed(num2) == 0) begin
                        result <= 9999; // err code
                        display_value <= 9999;
                        led <= 16'b0;
                    end
                    else begin
                        result <= $signed(num1) % $signed(num2);
                        display_value <= $signed(num1) % $signed(num2);
                        led <= {($signed(num1) % $signed(num2)) < 0 ? 1'b1 : 1'b0, 15'b0};
                    end
                end
                6: begin // exp (pwr)
                    // handle special cases for exp
                    if ($signed(num2) < 0) begin
                        result <= 9998; // err code for neg exp
                        display_value <= 9998;
                        led <= 16'b0;
                    end
                    else if ($signed(num2) == 0) begin
                        result <= 1; // anything^0 = 1 duh
                        display_value <= 1;
                        led <= 16'b0;
                    end
                    else begin
                        // start exp calc
                        power_result <= 1;
                        power_counter <= 0;
                        power_calculating <= 1;
                    end
                end
                7: begin // neg
                    result <= -$signed(num1);
                    display_value <= -$signed(num1);
                    led <= {(-$signed(num1)) < 0 ? 1'b1 : 1'b0, 15'b0};
                end
                default: begin // no op
                    result <= $signed(num1); // default to just show num1
                    display_value <= $signed(num1);
                    led <= {$signed(num1) < 0 ? 1'b1 : 1'b0, 15'b0};
                end
            endcase
        end
        
        // extract digits for disp
        abs_value = (display_value < 0) ? -display_value : display_value;
        digit1 = abs_value % 10;
        digit2 = (abs_value / 10) % 10;
        digit3 = (abs_value / 100) % 10;
        digit4 = (abs_value / 1000) % 10;
        digit5 = (abs_value / 10000) % 10;
        digit6 = (abs_value / 100000) % 10;
        
        // disp refresh cntr for main disp
        if (refresh_counter >= COUNT_MAX) begin
            refresh_counter <= 0;
            if (digit_select == 2'd3) begin  // reset after 4 digits (0-3)
                digit_select <= 0;
            end 
            else begin
                digit_select <= digit_select + 1;
            end
        end
        else begin
            refresh_counter <= refresh_counter + 1;
        end
    end
    
    // onboard disp ctrl process
    always @(*) begin
        // default all anodes off (active low)
        an = 4'b1111;
        
        // select which digit to show on main disp
        case (digit_select)
            2'd0: begin // rightmost digit (AN0)
                an = 4'b1110;
                seg = to_7seg(digit1);
            end
            2'd1: begin // 2nd from right (AN1)
                an = 4'b1101;
                seg = to_7seg(digit2);
            end
            2'd2: begin // 2nd from left (AN2)
                an = 4'b1011;
                seg = to_7seg(digit3);
            end
            2'd3: begin // leftmost digit (AN3)
                an = 4'b0111;
                // for neg nums, just show abs val & let LED show neg
                seg = to_7seg(digit4);
            end
            default: an = 4'b1111; // all digits off
        endcase
    end
    
    // func to cvt digit to 7seg pattern (active low for common anode)
    function [6:0] to_7seg;
        input [3:0] digit;
        begin
            case (digit)
                4'd0: to_7seg = 7'b1000000; // "0"
                4'd1: to_7seg = 7'b1111001; // "1"
                4'd2: to_7seg = 7'b0100100; // "2"
                4'd3: to_7seg = 7'b0110000; // "3"
                4'd4: to_7seg = 7'b0011001; // "4"
                4'd5: to_7seg = 7'b0010010; // "5"
                4'd6: to_7seg = 7'b0000010; // "6"
                4'd7: to_7seg = 7'b1111000; // "7"
                4'd8: to_7seg = 7'b0000000; // "8"
                4'd9: to_7seg = 7'b0010000; // "9"
                default: to_7seg = 7'b1111111; // all segs off
            endcase
        end
    endfunction

endmodule