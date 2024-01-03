module main (
    input clk,

    input [63:0] s_axis_tdata, 
    input [7:0] s_axis_tkeep, 
    input s_axis_tlast,
    input s_axis_tvalid, 

    output reg [63:0] m_axis_tdata, 
    output reg [7:0] m_axis_tkeep, 
    output reg m_axis_tlast,
    output m_axis_tvalid, 
    output s_axis_tready);

    `define WIDTH 104
    `define hash_len 16
    `define id_space (1<<`hash_len)

    reg [31:0] src_ip;
    reg [31:0] dst_ip; 
    reg [15:0] src_port; 
    reg [15:0] dst_port; 
    reg [7:0] protocol;

    reg [31:0] byte_cnt = 0;
    reg is_ip = 0;
    reg tready = 1;
    reg tvalid = 0;
    assign s_axis_tready = tready;
    assign m_axis_tvalid = tvalid;

    wire [`hash_len-1:0] hash_value = src_ip ^ dst_ip ^ src_port ^ dst_port ^ protocol;
    reg [`hash_len-1:0] loc_to_probe = 0;
    reg hash_stage = 0;
    reg probe_stage = 0;

    // map connection from id to tuple5. All zero represents no connection
    reg [`WIDTH-1:0] conn_mem [0:`id_space];
    integer i;
    initial begin
        for (i = 0; i <= `id_space; i = i + 1) begin
            conn_mem[i] = 0;
        end
        m_axis_tlast <= 0;
    end

    initial begin
        $dumpvars(clk, s_axis_tvalid, s_axis_tdata, s_axis_tkeep, s_axis_tlast, s_axis_tready, tvalid, tready, 
            m_axis_tdata, m_axis_tkeep, m_axis_tlast, m_axis_tvalid, byte_cnt, is_ip, protocol, hash_stage, probe_stage, loc_to_probe, hash_value);
    end    

    always @(posedge clk) begin
        if (s_axis_tvalid && s_axis_tready) begin
            // Copy the input to the output
            m_axis_tdata <= s_axis_tdata;
            m_axis_tkeep <= s_axis_tkeep;
            m_axis_tlast <= s_axis_tlast;
            tvalid <= 1;
            
            // Extract the 5-tuple from the input
            case (byte_cnt)
                16: begin
                    // Check if the packet is IP
                    if (s_axis_tdata[39:32] == 8'h08 && s_axis_tdata[47:40] == 8'h00) begin
                        is_ip <= 1;
                    end
                end
                24: begin
                    protocol <= s_axis_tdata[63:56];
                end
                32: begin
                    src_ip <= s_axis_tdata[47:16];
                    dst_ip[15:0] <= s_axis_tdata[63:48];
                end
                40: begin
                    dst_ip[31:16] <= s_axis_tdata[15:0];
                    src_port <= s_axis_tdata[31:16];
                    dst_port <= s_axis_tdata[47:32];
                    if (is_ip && protocol == 8'h06) begin
                        hash_stage <= 1;
                        tready <= 0;
                        tvalid <= 0; 
                    end
                end
            endcase
            
            // Update the byte count
            byte_cnt <= byte_cnt + 8;
            if (s_axis_tlast) begin
                // Reset the byte count
                byte_cnt <= 0;
                is_ip <= 0;
            end
        end else if (hash_stage) begin
            if (conn_mem[hash_value] == { src_ip, dst_ip, src_port, dst_port, protocol } || conn_mem[hash_value] == 0) begin
                conn_mem[hash_value] <= { src_ip, dst_ip, src_port, dst_port, protocol };
                hash_stage <= 0;
                tready <= 1;
                tvalid <= 1;
                m_axis_tdata[47:32] <= hash_value; // store hash value into dst_port
            end else begin
                hash_stage <= 0;
                probe_stage <= 1;
                loc_to_probe <= hash_value + 1;
            end
        end else if (probe_stage) begin
            // linear probe
            if (conn_mem[loc_to_probe] == { src_ip, dst_ip, src_port, dst_port, protocol } || conn_mem[loc_to_probe] == 0) begin
                conn_mem[loc_to_probe] <= { src_ip, dst_ip, src_port, dst_port, protocol };
                probe_stage <= 0;
                tready <= 1;
                tvalid <= 1;
                m_axis_tdata[47:32] <= loc_to_probe; // store hash value into dst_port
            end else begin
                loc_to_probe <= loc_to_probe + 1;
            end
        end
    end

endmodule
