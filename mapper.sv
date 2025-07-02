module mapper #(
    parameter DIM4_WIDTH = 8,  
    parameter DIM3_WIDTH = 8, 
    parameter DIM2_WIDTH = 8,  
    parameter DIM1_WIDTH = 8,
    
    parameter IDX4_WIDTH = 8,  
    parameter IDX3_WIDTH = 8, 
    parameter IDX2_WIDTH = 8,  
    parameter IDX1_WIDTH = 8,
        
    parameter ROW_MAJOR = 1,   
    parameter ADDR_WIDTH = 32 
)( 
    input  logic                        clk,           // Added clock input
    input  logic                        rst,           // Added reset input
    input  logic [DIM4_WIDTH - 1:0]     dim4, 
    input  logic [DIM3_WIDTH - 1:0]     dim3, 
    input  logic [DIM2_WIDTH - 1:0]     dim2,
    input  logic [DIM1_WIDTH - 1:0]     dim1,
    
    input  logic [IDX4_WIDTH - 1:0]     idx4,
    input  logic [IDX3_WIDTH - 1:0]     idx3, 
    input  logic [IDX2_WIDTH - 1:0]     idx2,
    input  logic [IDX1_WIDTH - 1:0]     idx1,
    
    input  logic [ADDR_WIDTH - 1:0]     base_addr,
    output logic [ADDR_WIDTH - 1:0]     addr
);

    // Internal signals for pipeline stages
    logic [ADDR_WIDTH - 1:0] mult1_result, mult2_result, mult3_result;
    logic [ADDR_WIDTH - 1:0] dim3_dim2_dim1, dim2_dim1;
    logic [ADDR_WIDTH - 1:0] addr_temp;
    
    generate
        if (ROW_MAJOR) begin : row_major_block
            // Pipeline stage 1: Compute dimensional products
            always_ff @(negedge clk or posedge rst) begin
                if (rst) begin
                    dim2_dim1 <= '0;
                    dim3_dim2_dim1 <= '0;
                end else begin
                    dim2_dim1 <= dim2 * dim1;
                    dim3_dim2_dim1 <= dim3 * dim2 * dim1;
                end
            end

            // Pipeline stage 2: Compute partial products
            always_ff @(negedge clk or posedge rst) begin
                if (rst) begin
                    mult1_result <= '0;
                    mult2_result <= '0;
                    mult3_result <= '0;
                end else begin
                    mult1_result <= idx4 * dim3_dim2_dim1;
                    mult2_result <= idx3 * dim2_dim1;
                    mult3_result <= idx2 * dim1;
                end
            end

            // Pipeline stage 3: Sum up all components
            always_ff @(negedge clk or posedge rst) begin
                if (rst) begin
                    addr_temp <= '0;
                end else begin
                    addr_temp <= base_addr + mult1_result + mult2_result + mult3_result + idx1;
                end
            end

        end else begin : column_major_block
            // Pipeline stage 1: Compute dimensional products
            always_ff @(negedge clk or posedge rst) begin
                if (rst) begin
                    dim2_dim1 <= '0;
                    dim3_dim2_dim1 <= '0;
                end else begin
                    dim2_dim1 <= dim2 * dim1;
                    dim3_dim2_dim1 <= dim3 * dim2 * dim1;
                end
            end

            // Pipeline stage 2: Compute partial products
            always_ff @(negedge clk or posedge rst) begin
                if (rst) begin
                    mult1_result <= '0;
                    mult2_result <= '0;
                    mult3_result <= '0;
                end else begin
                    mult1_result <= idx4 * dim3_dim2_dim1;
                    mult2_result <= idx3 * dim2_dim1;
                    mult3_result <= idx1 * dim2;
                end
            end

            // Pipeline stage 3: Sum up all components
            always_ff @(negedge clk or posedge rst) begin
                if (rst) begin
                    addr_temp <= '0;
                end else begin
                    addr_temp <= base_addr + mult1_result + mult2_result + mult3_result + idx2;
                end
            end
        end
    endgenerate

    // Final assignment
    assign addr = addr_temp;

endmodule
