onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate    -group cu       -radix hex /top/a0/f0/c0/cu0/*
add wave -noupdate    -group control  -radix hex /top/a0/f0/c0/*
add wave -noupdate -r -group mmio     -radix hex /top/a0/f0/m0/*
add wave -noupdate    -group dma      -radix hex /top/a0/f0/d0/*
add wave -noupdate    -group pe0_add_alpha_beta   -radix hex /top/a0/f0/c0/cu0/pairhmm_core/P(0)/F/PECORE/add_alpha_beta/*

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
quietly wave cursor active 0
configure wave -namecolwidth 300
configure wave -valuecolwidth 300
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
config wave -signalnamewidth 1
update
WaveRestoreZoom {0 ns} {1 us}
