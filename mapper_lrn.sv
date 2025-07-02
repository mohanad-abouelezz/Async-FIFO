//*********************************************************************************\\
/*  * DATE: 2025-05-02
    Engineer: Mohanned Abou-el-ezz 
    * mapper_lrn.sv
    * Mapper LRN module for handling address generation and control signals
    * Features:
        - Handle address generation for read & write for 4 dimensions
          (patch, depth, height, width)
        - Control signals (normalized_layer) after writing all pixels in the memory 
    
    * Features to be Handled isa:
        - Handling COL_MAJOR (Now we ONLY handle ROW_MAJOR)
*/
//*********************************************************************************\\
module mapper_lrn #(
    parameter N_WIDTH = 2,    // Maximum number of batches (N = 4)
    parameter M_WIDTH = 10,    // Maximum number of output feature maps 
    parameter E_WIDTH = 6,    // Maximum height of output feature maps 
    parameter F_WIDTH = 6,    // Maximum width of output feature maps 
    parameter V_WIDTH = 2,    // Maximum padding number

    parameter ADDR_BUS_WIDTH = 20,    // Bus width for the address
    parameter DATA_WIDTH     = 16,    // Width of one data word from GLB
    parameter ROW_MAJOR      = 1     // 1 = Row-major, 0 = Column-major
)(
    input  logic                             core_clk,               // Clock signal
    input  logic                             reset,                  // Active-high reset
    input  logic                             start_normalization,    // Configuration enable
    input  logic [N_WIDTH- 1 : 0]            dim4,                   // Number of batches (N = 4)
    input  logic [M_WIDTH- 1 : 0]            dim3,                   // Number of output feature maps
    input  logic [E_WIDTH- 1 : 0]            dim2,                   // Height of output feature maps
    input  logic [F_WIDTH- 1 : 0]            dim1,                   // Width of output feature maps
    input  logic [V_WIDTH- 1 : 0]            padding_num,            // Padding size
    input  logic                             normalized_window,   // flag signal from LRN after normalizing one pixel in all depths 
    input  logic                             full_flag,              // flag from LRN to wait the div_out_valid (can be considered extra wait)
    input  logic                             div_out_valid,          // one pulse high with each normalized pixel out from the divider
    output logic [ADDR_BUS_WIDTH - 1 : 0]    r_addr,                 // Computed output address
    output logic                             r_enable,               // Write enable signal for the output address
    output logic [ADDR_BUS_WIDTH - 1 : 0]    w_addr,                 // Computed output address
    output logic                             w_enable,               // Write enable signal for the output address
    output logic                             normalized_layer        // flag asserted to one to start padding the ifmap (by padding unit) 
);  

/*---------------------- Handling Padding & Generating address --------------------------------------*/

    //internal singals 
    logic [(F_WIDTH + E_WIDTH + M_WIDTH) - 1 : 0]  normalized_pixels_count;

    // Adjust dimensions to include padding
    logic [E_WIDTH- 1 : 0] padded_dim2;
    logic [F_WIDTH- 1 : 0] padded_dim1;

    // Generate indcies internally to get the address
    logic [N_WIDTH- 1 : 0]  idx4_w;
    logic [M_WIDTH- 1 : 0]  idx3_w;
    logic [E_WIDTH- 1 : 0]  idx2_w;
    logic [F_WIDTH- 1 : 0]  idx1_w;

    logic [N_WIDTH- 1 : 0]  idx4_r;
    logic [M_WIDTH- 1 : 0]  idx3_r;
    logic [E_WIDTH- 1 : 0]  idx2_r;
    logic [F_WIDTH- 1 : 0]  idx1_r;

    // We consider the padding ONLY while writing 
    always_comb begin
        padded_dim2 = dim2 + (2 * padding_num);
        padded_dim1 = dim1 + (2 * padding_num);
    end

/*--------------------------- Address computation --------------------------------------*/
    // Instanitiate the Multiplier & cla_modified Modules instead of using the DSP Block
    logic [F_WIDTH + E_WIDTH - 1 : 0] r_temp_1, r_temp_2; 
    logic [F_WIDTH + E_WIDTH + M_WIDTH - 1 : 0] r_temp_3,r_temp_4; 
    logic [F_WIDTH + E_WIDTH + M_WIDTH + N_WIDTH - 1 : 0] r_temp_5;

    logic [V_WIDTH + E_WIDTH - 1 : 0] w_temp_1; 
    logic [V_WIDTH + F_WIDTH - 1 : 0] w_temp_2; 
    logic [E_WIDTH + V_WIDTH + F_WIDTH - 1 : 0] w_temp_3; 
    logic [F_WIDTH + E_WIDTH - 1 : 0] w_temp_4; 
    logic [F_WIDTH + E_WIDTH + M_WIDTH - 1 : 0] w_temp_5,w_temp_6; 
    logic [F_WIDTH + E_WIDTH + M_WIDTH + N_WIDTH- 1 : 0] w_temp_7;

    // Address computation for read operation
    unsigned_wallace_tree_multiplier_modified #(.in1_width(F_WIDTH),.in2_width(E_WIDTH))R_1(
        .in1(idx1_r),
        .in2(dim2),
        .out(r_temp_1)
    );

    unsigned_wallace_tree_multiplier_modified #(.in1_width(F_WIDTH),.in2_width(E_WIDTH))R_2(
        .in1(dim1),
        .in2(dim2),
        .out(r_temp_2)
    );

    unsigned_wallace_tree_multiplier_modified #(.in1_width(F_WIDTH + E_WIDTH),.in2_width(M_WIDTH))R_3(
        .in1(r_temp_2),
        .in2(idx3_r),
        .out(r_temp_3)
    );

    unsigned_wallace_tree_multiplier_modified #(.in1_width(F_WIDTH + E_WIDTH),.in2_width(M_WIDTH))R_4(
        .in1(r_temp_2),
        .in2(dim3),
        .out(r_temp_4)
    );

    unsigned_wallace_tree_multiplier_modified #(.in1_width(F_WIDTH + E_WIDTH + M_WIDTH),.in2_width(N_WIDTH))R_5(
        .in1(r_temp_4),
        .in2(idx4_r),
        .out(r_temp_5)
    );

    assign r_addr = r_temp_5 + r_temp_3 + r_temp_1 + idx2_r;

     
/*--------------------- Address computation for write operation-------------------*/
    cla_modified #(.width_x(V_WIDTH),.width_y(E_WIDTH),.width_sum(V_WIDTH + E_WIDTH)) W_1(
        .x(padding_num),
        .y(idx2_w),
        .sum(w_temp_1)
    );

    cla_modified #(.width_x(V_WIDTH),.width_y(F_WIDTH),.width_sum(V_WIDTH + F_WIDTH)) W_2(
        .x(padding_num),
        .y(idx1_w),
        .sum(w_temp_2)
    );

    unsigned_wallace_tree_multiplier_modified #(.in1_width(E_WIDTH),.in2_width(V_WIDTH + F_WIDTH))W_3(
        .in1(padded_dim2),
        .in2(w_temp_2),
        .out(w_temp_3)
    );

    unsigned_wallace_tree_multiplier_modified #(.in1_width(F_WIDTH),.in2_width(E_WIDTH))W_4(
        .in1(padded_dim1),
        .in2(padded_dim2),
        .out(w_temp_4)
    );

    unsigned_wallace_tree_multiplier_modified #(.in1_width(F_WIDTH + E_WIDTH),.in2_width(M_WIDTH))W_5(
        .in1(w_temp_4),
        .in2(idx3_w),
        .out(w_temp_5)
    );
 
    unsigned_wallace_tree_multiplier_modified #(.in1_width(F_WIDTH + E_WIDTH),.in2_width(M_WIDTH))W_6(
        .in1(w_temp_4),
        .in2(dim3),
        .out(w_temp_6)
    );
   
    unsigned_wallace_tree_multiplier_modified #(.in1_width(F_WIDTH + E_WIDTH + M_WIDTH),.in2_width(N_WIDTH))W_7(
        .in1(w_temp_6),
        .in2(idx4_w),
        .out(w_temp_7)
    );

    assign w_addr = w_temp_7 + w_temp_5 + w_temp_3 + w_temp_1;

/*----------------------------------------Control part (FSM) -------------------------------------*/
    //state encoding
    typedef enum logic [2:0] {IDLE, WAIT, READ, PROCESS, WRITE} state_t;
    
    (* fsm_encoding = "gray" *)
    state_t current_state, next_state;

    // State Memory
    always_ff @ (posedge core_clk or posedge reset)
    begin
        if (reset)
            current_state <= IDLE;
        else 
            current_state <= next_state;
    end  

    // Next State Logic
    always @(*) begin
        case(current_state) 
            IDLE  : next_state = (start_normalization) ? READ : IDLE;

            READ  : begin 
                if(full_flag) begin
                    next_state = PROCESS; 
                end else begin
                    next_state = READ; 
                end
            end 

            PROCESS: begin
                if(normalized_layer) begin
                    next_state = IDLE; 
                end
                else if(div_out_valid) begin
                    next_state = WRITE;         
                end else if (normalized_window) begin
                    next_state = WAIT;
                end else begin
                    next_state = PROCESS;       
                end

            end

            WRITE  : begin
               // if(normalized_window) begin
               //     next_state = WAIT; 
               // end
                 if(!normalized_window) begin
                    next_state = PROCESS;           
                end
                else begin
                    next_state = WRITE;             
                end
            end 

            WAIT   : begin
                next_state = READ; 
            end

            default: next_state = IDLE;

        endcase 
    end

    // Output Logic
    always_ff @ (posedge core_clk or posedge reset) begin
        if (reset) begin
            idx4_r <= 0;
            idx3_r <= 0;
            idx2_r <= 0;
            idx1_r <= 0;
            idx4_w <= 0;
            idx3_w <= 0;
            idx2_w <= 0;
            idx1_w <= 0;
            w_enable <= 0;
            r_enable <= 0;
            normalized_pixels_count <= 0;
            normalized_layer <= 0;
        end
        else begin
            case (current_state)
                IDLE: begin
                    // Reset all indices and flags
                    idx4_r <= 0;
                    idx3_r <= 0;
                    idx2_r <= 0;
                    idx1_r <= 0;
                    idx4_w <= 0;
                    idx3_w <= 0;
                    idx2_w <= 0;
                    idx1_w <= 0;
                    w_enable <= 0;
                    r_enable <= 0;
                    normalized_pixels_count <= 0;
                    normalized_layer <= 0;

                    if(next_state == READ) r_enable <= 1;
                end

                READ: begin
                   // Use stored values when returning from WAIT state
                        w_enable <= 0;
                        if (idx3_r == dim3-1) r_enable <= 0;
                        // Outer loop
                        if(r_enable) begin
                            if (idx4_r == dim4-1) begin
                                idx4_r <= 0;
                                if (idx3_r == dim3-1) begin
                                    idx3_r <= 0;
                                    if (idx2_r == dim2-1) begin
                                        idx2_r <= 0;
                                        if (idx1_r == dim1-1) begin
                                            idx1_r <= 0;
                                        end
                                        else begin
                                            idx1_r <= idx1_r + 1;
                                        end
                                    end
                                    else idx2_r <= idx2_r + 1;
                                end
                                else idx3_r <= idx3_r + 1;
                            end
                            else idx4_r <= idx4_r + 1;
                        end
                end

                PROCESS: begin
                    r_enable <= 0;
                    normalized_layer <= 0; 
                    if(div_out_valid) begin
                        w_enable <= 1;
                        normalized_pixels_count <= normalized_pixels_count + 1;
                    end
                end

                WRITE: begin
                    // Use stored values when returning from WAIT state
                        r_enable <= 0;
                        w_enable <= 0;
        
                        if (normalized_pixels_count == dim1 * dim2 * dim3 * dim4) begin
                                normalized_pixels_count <= 0;
                                normalized_layer        <= 1;       // Set the flag to indicate that the layer is normalized
                        end

                        if (w_enable) begin
                        // Outer loop
                        if (idx4_w == dim4-1) begin
                                idx4_w <= 0;
                                if (idx3_w == dim3-1) begin
                                    idx3_w <= 0;
                                    if (idx2_w == dim2-1) begin
                                        idx2_w <= 0;
                                        if (idx1_w == dim1-1) begin
                                            idx1_w <= 0;
                                        end
                                        else begin
                                            idx1_w <= idx1_w + 1;
                                        end
                                    end
                                    else idx2_w <= idx2_w + 1;
                                end
                                else idx3_w <= idx3_w + 1;
                            end
                            else idx4_w <= idx4_w + 1;
                        end              
                end

                WAIT: begin
                    if(next_state == IDLE) r_enable <= 0;
                    else                   r_enable <= 1;
                    normalized_layer <= 0;
                end
                
            endcase 
        end
    end

endmodule
