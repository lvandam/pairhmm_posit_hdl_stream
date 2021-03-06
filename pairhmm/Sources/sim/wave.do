onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate    -group cu       -radix hex /top/a0/f0/c0/cu0/*
add wave -noupdate    -group control  -radix hex /top/a0/f0/c0/*
add wave -noupdate -r -group mmio     -radix hex /top/a0/f0/m0/*
add wave -noupdate    -group dma      -radix hex /top/a0/f0/d0/*

add wave -position end -group resm sim:/top/a0/f0/c0/cu0/pairhmm_core/resbusm
add wave -position end -group resm sim:/top/a0/f0/c0/cu0/pairhmm_core/resaccum_m/in1
add wave -position end -group resm sim:/top/a0/f0/c0/cu0/pairhmm_core/resaccum_m/result
add wave -position end -group resi sim:/top/a0/f0/c0/cu0/pairhmm_core/resbusi
add wave -position end -group resi sim:/top/a0/f0/c0/cu0/pairhmm_core/resaccum_i/in1
add wave -position end -group resi sim:/top/a0/f0/c0/cu0/pairhmm_core/resaccum_i/result
add wave -position end -group resaccum sim:/top/a0/f0/c0/cu0/pairhmm_core/resaccum/in1
add wave -position end -group resaccum sim:/top/a0/f0/c0/cu0/pairhmm_core/resaccum/in2
add wave -position end -group resaccum sim:/top/a0/f0/c0/cu0/pairhmm_core/resaccum/result

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
