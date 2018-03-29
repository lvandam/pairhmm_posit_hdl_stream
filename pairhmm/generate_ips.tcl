# Generate a Simple Dual-Port Ram
proc gen_ramblock {width depth mode} {
#  set width   1024
#  set depth   256

  set modname sdpr_$width\_$depth\_$mode

  puts "Creating Simple Dual-Port Ram..."
  puts $modname

  create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.2 -module_name $modname -dir cores/ -force

  set_property -dict [list  CONFIG.Memory_Type                                {Simple_Dual_Port_RAM}  \
                            CONFIG.Assume_Synchronous_Clk                     {true}                  \
                            CONFIG.Write_Width_A                              $width                  \
                            CONFIG.Write_Depth_A                              $depth                  \
                            CONFIG.Operating_Mode_A                           $mode                   \
                            CONFIG.Enable_A                                   {Always_Enabled}        \
                            CONFIG.Enable_B                                   {Always_Enabled}        \
                            CONFIG.Read_Width_A                               $width                  \
                            CONFIG.Write_Width_B                              $width                  \
                            CONFIG.Read_Width_B                               $width                  \
                            CONFIG.Operating_Mode_B                           {READ_FIRST}            \
                            CONFIG.Register_PortA_Output_of_Memory_Primitives {false}                 \
                            CONFIG.Register_PortB_Output_of_Memory_Primitives {true}                  \
                            CONFIG.Port_B_Clock                               {100}                   \
                            CONFIG.Port_B_Write_Rate                          {0}                     \
                            CONFIG.Port_B_Enable_Rate                         {100}]                  \
                            [get_ips $modname]                                         
                                      
  generate_target synthesis [get_files cores/$modname/$modname.xci]
#  create_ip_run [get_files -of_objects [get_fileset sources_1] vivado/ramgen.srcs/sources_1/ip/$modname/$modname.xci]
}

# Generate a FIFO:
proc gen_fifo {width depth mode} {

  set modname fifo_$width\_$depth\_$mode
  
  puts "Creating Simple Dual-Port Ram..."
  puts $modname
  
  create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.0 -module_name $modname -dir cores/ -force
  
  set_property -dict [list \
  CONFIG.Fifo_Implementation {Common_Clock_Builtin_FIFO} \
  CONFIG.Performance_Options $mode \
  CONFIG.Input_Data_Width $width \
  CONFIG.Input_Depth $depth \
  CONFIG.Output_Data_Width $width \
  CONFIG.Output_Depth $depth \
  ] \
  [get_ips $modname]
  
  generate_target synthesis [get_files cores/$modname/$modname.xci]
}

### Main script:

# can we do this with -in_memory ?: 
create_project -force ipgen vivado -part xc7vx690tffg1157-2 

#set_property board_part alpha-data.com:adm-pcie-7v3:part0:1.1 [current_project]
set_property target_language VHDL [current_project]
set_property simulator_language VHDL [current_project]

#gen_ramblock 1024 256 WRITE_FIRST
#gen_ramblock 128 256 WRITE_FIRST
#gen_ramblock 1024 256 READ_FIRST

gen_fifo 1024 1024 First_Word_Fall_Through


################# Generate
#launch_run -jobs 8 $modname\_synth_1
#wait_on_run $modname\_synth_1

