module mapper_lrn #(
    parameter N_WIDTH = 2,    // Maximum number of batches (N = 4)
    parameter M_WIDTH = 10,   // Maximum number of output feature maps 
    parameter E_WIDTH = 6,    // Maximum height of output feature maps 
    parameter F_WIDTH = 6,    // Maximum width of output feature maps 
    parameter V_WIDTH = 2,    // Maximum padding number
    parameter ADDR_BUS_WIDTH = 20,    // Bus width for the address
    parameter DATA_WIDTH     = 16,    // Width of one data word from GLB
    parameter ROW_MAJOR      = 1     // 1 = Row-major, 0 = Column-major
)(
    input  logic                             core_clk,               
    input  logic                             reset,                  
    input  logic                             start_normalization,    
    input  logic [N_WIDTH- 1 : 0]            dim4,                   
    input  logic [M_WIDTH- 1 : 0]            dim3,                   
    input  logic [E_WIDTH- 1 : 0]            dim2,                   
    input  logic [F_WIDTH- 1 : 0]            dim1,                   
    input  logic [V_WIDTH- 1 : 0]            padding_num,            
    input  logic                             normalized_window,   
    input  logic                             full_flag,              
    input  logic                             div_out_valid,          
    output logic [ADDR_BUS_WIDTH - 1 : 0]    r_addr,                 
    output logic                             r_enable,               
    output logic [ADDR_BUS_WIDTH - 1 : 0]    w_addr,                 
    output logic                             w_enable,               
    output logic                             normalized_layer        
);  

    // Internal signals
    logic [(F_WIDTH + E_WIDTH + M_WIDTH) - 1 : 0] normalized_pixels_count;
    logic [E_WIDTH- 1 : 0] padded_dim2;
    logic [F_WIDTH- 1 : 0] padded_dim1;
    logic [N_WIDTH- 1 : 0] idx4_w, idx4_r;
    logic [M_WIDTH- 1 : 0] idx3_w, idx3_r;
    logic [E_WIDTH- 1 : 0] idx2_w, idx2_r;
    logic [F_WIDTH- 1 : 0] idx1_w, idx1_r;

    // New signals for timing improvement
    logic increment_indices_w;
    logic indices_at_max_w;
    logic [3:0] index_stage;
    logic next_idx1_w, next_idx2_w, next_idx3_w, next_idx4_w;
    logic idx1_max, idx2_max, idx3_max, idx4_max;
    logic [ADDR_BUS_WIDTH-1:0] w_addr_temp, r_addr_temp;

    // Padding calculation
    always_comb begin
        padded_dim2 = dim2 + (2 * padding_num);
        padded_dim1 = dim1 + (2 * padding_num);
    end

    // Address computation signals
    logic [F_WIDTH + E_WIDTH - 1 : 0] r_temp_1, r_temp_2; 
    logic [F_WIDTH + E_WIDTH + M_WIDTH - 1 : 0] r_temp_3, r_temp_4; 
    logic [F_WIDTH + E_WIDTH + M_WIDTH + N_WIDTH - 1 : 0] r_temp_5;

    logic [V_WIDTH + E_WIDTH - 1 : 0] w_temp_1; 
    logic [V_WIDTH + F_WIDTH - 1 : 0] w_temp_2; 
    logic [E_WIDTH + V_WIDTH + F_WIDTH - 1 : 0] w_temp_3; 
    logic [F_WIDTH + E_WIDTH - 1 : 0] w_temp_4; 
    logic [F_WIDTH + E_WIDTH + M_WIDTH - 1 : 0] w_temp_5, w_temp_6; 
    logic [F_WIDTH + E_WIDTH + M_WIDTH + N_WIDTH- 1 : 0] w_temp_7;

    // Register comparison results
    always_ff @(posedge core_clk or posedge reset) begin
        if (reset) begin
            idx1_max <= 0;
            idx2_max <= 0;
            idx3_max <= 0;
            idx4_max <= 0;
        end else begin
            idx1_max <= (idx1_w == dim1-1);
            idx2_max <= (idx2_w == dim2-1);
            idx3_max <= (idx3_w == dim3-1);
            idx4_max <= (idx4_w == dim4-1);
        end
    end

    // Separate block for index calculations
    always_ff @(posedge core_clk or posedge reset) begin
        if (reset) begin
            next_idx1_w <= 0;
            next_idx2_w <= 0;
            next_idx3_w <= 0;
            next_idx4_w <= 0;
            index_stage <= 0;
        end else if (increment_indices_w) begin
            case (index_stage)
                0: begin
                    next_idx4_w <= idx4_max ? 0 : idx4_w + 1;
                    index_stage <= 1;
                end
                1: begin
                    if (idx4_max) begin
                        next_idx3_w <= idx3_max ? 0 : idx3_w + 1;
                    end
                    index_stage <= 2;
                end
                2: begin
                    if (idx4_max && idx3_max) begin
                        next_idx2_w <= idx2_max ? 0 : idx2_w + 1;
                    end
                    index_stage <= 3;
                end
                3: begin
                    if (idx4_max && idx3_max && idx2_max) begin
                        next_idx1_w <= idx1_max ? 0 : idx1_w + 1;
                    end
                    index_stage <= 0;
                end
            endcase
        end
    end

    // Address computation instantiations
    unsigned_wallace_tree_multiplier_modified #(.in1_width(F_WIDTH),.in2_width(E_WIDTH)) R_1(
        .in1(idx1_r),
        .in2(dim2),
        .out(r_temp_1)
    );

    // ... [Keep all your existing multiplier instantiations] ...

    // Pipeline address calculations
    always_ff @(posedge core_clk) begin
        if (reset) begin
            w_addr_temp <= 0;
            r_addr_temp <= 0;
        end else begin
            w_addr_temp <= w_temp_7 + w_temp_5 + w_temp_3 + w_temp_1;
            r_addr_temp <= r_temp_5 + r_temp_3 + r_temp_1 + idx2_r;
        end
    end

    assign w_addr = w_addr_temp;
    assign r_addr = r_addr_temp;

    // State definitions
    typedef enum logic [2:0] {IDLE, WAIT, READ, PROCESS, WRITE} state_t;
    
    (* fsm_encoding = "gray" *)
    state_t current_state, next_state;

    // State Memory
    always_ff @(posedge core_clk or posedge reset) begin
        if (reset)
            current_state <= IDLE;
        else 
            current_state <= next_state;
    end  

    // Next State Logic
    always_comb begin
        case(current_state) 
            IDLE: next_state = (start_normalization) ? READ : IDLE;
            
            READ: begin 
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

            WRITE: begin
                if(!normalized_window) begin
                    next_state = PROCESS;           
                end
                else begin
                    next_state = WRITE;             
                end
            end 

            WAIT: begin
                next_state = READ; 
            end

            default: next_state = IDLE;
        endcase 
    end

    // Output Logic
    always_ff @(posedge core_clk or posedge reset) begin
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
            increment_indices_w <= 0;
        end
        else begin
            case (current_state)
                IDLE: begin
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
                    increment_indices_w <= 0;

                    if(next_state == READ) r_enable <= 1;
                end

                READ: begin
                    w_enable <= 0;
                    if (idx3_r == dim3-1) r_enable <= 0;
                    
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
                    increment_indices_w <= 0;
                    if(div_out_valid) begin
                        w_enable <= 1;
                        normalized_pixels_count <= normalized_pixels_count + 1;
                    end
                end

                WRITE: begin
                    r_enable <= 0;
                    w_enable <= 0;
        
                    if (normalized_pixels_count == dim1 * dim2 * dim3 * dim4) begin
                        normalized_pixels_count <= 0;
                        normalized_layer <= 1;
                    end

                    if (w_enable) begin
                        increment_indices_w <= 1;
                        idx4_w <= next_idx4_w;
                        idx3_w <= next_idx3_w;
                        idx2_w <= next_idx2_w;
                        idx1_w <= next_idx1_w;
                    end else begin
                        increment_indices_w <= 0;
                    end
                end

                WAIT: begin
                    if(next_state == IDLE) r_enable <= 0;
                    else                   r_enable <= 1;
                    normalized_layer <= 0;
                    increment_indices_w <= 0;
                end
            endcase 
        end
    end

endmodule
