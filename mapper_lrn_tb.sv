//*********************************************************************************\\
/*  DATE: 2025-05-02
    Tested Features: Mapper LRN in case symmetric channel with and without padding
    DUT: mapper_lrn.sv

    Features to be tested isa:
        - Mapper LRN with symmetric channel with & without padding
        - Mapper LRN with patch (symmetric & Asymmetric channel with & without padding)  

    //Test case 3: 1x4x3x2, padding = 0  (Asymmetric channel without padding)
        initialize(1, 4, 3, 2, 0);              // Initialize with dimensions
        start_norm();                           // Start normalization

        repeat (dim3+1) begin
            simulate_reading(dim3);             // Simulate reading
            simulate_div_out_valid(dim3);       // Simulate div_out_valid
            simulate_normalized_window_rr();    // Simulate normalized_window_rr
            wait_clks(1);                       // Wait for one clock cycle
        end
        
        wait_clks(1);                           // Wait for one clock cycle


        //Test case 4: 1x4x3x2, padding = 1  (Asymmetric channel with padding)
        initialize(1, 4, 3, 2, 1);              // Initialize with dimensions
        start_norm();                           // Start normalization

        repeat (dim3+1) begin
            simulate_reading(dim3);             // Simulate reading
            simulate_div_out_valid(dim3);       // Simulate div_out_valid
            simulate_normalized_window_rr();    // Simulate normalized_window_rr
            wait_clks(1);                       // Wait for one clock cycle
        end
        
        wait_clks(1);                           // Wait for one clock cycle

        
        //Test case 5: 2x4x2x2, padding = 0    (patch of symmetric channels without padding)
        initialize(2, 4, 2, 2, 0);              // Initialize with dimensions
        start_norm();                           // Start normalization
        repeat(dim4) begin
            repeat (dim3+1) begin
                simulate_reading(dim3);             // Simulate reading
                simulate_div_out_valid(dim3);       // Simulate div_out_valid
                simulate_normalized_window_rr();    // Simulate normalized_window_rr
                wait_clks(1);                       // Wait for one clock cycle
            end
        end
        
        wait_clks(1);                           // Wait for one clock cycle

        //Test case 6: 2x4x2x2, padding = 1    (patch of symmetric channels without padding)
        initialize(2, 4, 2, 2, 1);              // Initialize with dimensions
        start_norm();                           // Start normalization
        repeat(dim4) begin
            repeat (dim3+1) begin
                simulate_reading(dim3);             // Simulate reading
                simulate_div_out_valid(dim3);       // Simulate div_out_valid
                simulate_normalized_window_rr();    // Simulate normalized_window_rr
                wait_clks(1);                       // Wait for one clock cycle
            end
        end
        
        wait_clks(1);                           // Wait for one clock cycle
*/
//*********************************************************************************\\
`timescale 1ns/1ps

module tb_mapper_lrn;

    // Parameters
    localparam N_WIDTH        = 2;
    localparam M_WIDTH        = 4;
    localparam E_WIDTH        = 4;
    localparam F_WIDTH        = 4;
    localparam V_WIDTH        = 2;
    localparam ADDR_BUS_WIDTH = 20;
    localparam DATA_WIDTH     = 16;
    localparam ROW_MAJOR      = 1;

    // DUT signals
    logic                         core_clk;
    logic                         reset;
    logic                         start_normalization;
    logic [N_WIDTH-1:0]           dim4;
    logic [M_WIDTH-1:0]           dim3;
    logic [E_WIDTH-1:0]           dim2;
    logic [F_WIDTH-1:0]           dim1;
    logic [V_WIDTH-1:0]           padding_num;
    logic                         normalized_window_rr;
    logic                         full_flag;
    logic                         div_out_valid;
    logic [ADDR_BUS_WIDTH-1:0]    r_addr, w_addr;
    logic                         r_enable, w_enable;
    logic                         normalized_layer;
  
  // Clock generator
  always #5 core_clk = ~core_clk;

    // DUT instantiation
    mapper_lrn #(
        .N_WIDTH(N_WIDTH),
        .M_WIDTH(M_WIDTH),
        .E_WIDTH(E_WIDTH),
        .F_WIDTH(F_WIDTH),
        .V_WIDTH(V_WIDTH),
        .ADDR_BUS_WIDTH(ADDR_BUS_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ROW_MAJOR(ROW_MAJOR)
    ) dut (
        .core_clk(core_clk),
        .reset(reset),
        .start_normalization(start_normalization),
        .dim4(dim4),
        .dim3(dim3),
        .dim2(dim2),
        .dim1(dim1),
        .padding_num(padding_num),
        .normalized_window_rr(normalized_window_rr),
        .full_flag(full_flag),
        .div_out_valid(div_out_valid),
        .r_addr(r_addr),
        .r_enable(r_enable),
        .w_addr(w_addr),
        .w_enable(w_enable),
        .normalized_layer(normalized_layer)
    );

    // Task: Wait for clock edges
    task wait_clks(input int num);
        repeat (num) @(posedge core_clk);
    endtask

    task initialize( input logic  [N_WIDTH-1:0] d4,[M_WIDTH-1:0] d3,[E_WIDTH-1:0] d2, 
                                  [F_WIDTH-1:0] d1,[V_WIDTH-1:0] v);
        dim4 = d4; 
        dim3 = d3;  
        dim2 = d2; 
        dim1 = d1; 
        padding_num = v;
        core_clk = 0;
        start_normalization = 0;
        normalized_window_rr = 0;
        full_flag = 0;
        div_out_valid = 0;
    endtask

    task assert_reset();
        reset = 1;
        wait_clks(1);
        reset = 0;
        wait_clks(1);
    endtask

    task start_norm();
        start_normalization = 1;
        wait_clks(1);
        start_normalization = 0;
        wait_clks(1);
    endtask

    task simulate_reading(input logic  [M_WIDTH-1:0] d3);
        wait_clks(dim3);
            full_flag = 1;   
        wait_clks(1);
            full_flag = 0; 
        wait_clks(1);
    endtask
    
    // Simulate LRN response
    // Trigger div_out_valid to proceed from PROCESS -> WRITE

    task simulate_div_out_valid(input logic [M_WIDTH-1:0] d3);
        repeat (dim3-1) begin
            div_out_valid = 1;
            wait_clks(1);
            div_out_valid = 0;
            wait_clks(1);
        end
    endtask

    task simulate_normalized_window_rr();
            div_out_valid = 1;
            wait_clks(1);
            div_out_valid = 0;
            normalized_window_rr = 1;
            wait_clks(1);
            normalized_window_rr = 0;  
    endtask

    initial begin
        core_clk = 0;
        reset = 1;

        //Test case 1: 1x4x2x2, padding = 0  (symmetric channel without padding)
        initialize(1, 4, 2, 2, 0);              // Initialize with dimensions
        assert_reset();                         // Assert reset
        start_norm();                           // Start normalization

        repeat (dim3+1) begin
            simulate_reading(dim3);             // Simulate reading
            simulate_div_out_valid(dim3);       // Simulate div_out_valid
            simulate_normalized_window_rr();    // Simulate normalized_window_rr
            wait_clks(2);                       // Wait 
        end
            
        //Test case 2: 1x4x2x2, padding = 1  (symmetric channel with padding)
        initialize(1, 4, 2, 2, 1);              
        start_norm();                           

        repeat (dim3+1) begin
            simulate_reading(dim3);             
            simulate_div_out_valid(dim3);       
            simulate_normalized_window_rr();    
            wait_clks(2);                             
        end
        
        #20;
        $display("[TB] Test finished.");
        $stop;
    end

endmodule
