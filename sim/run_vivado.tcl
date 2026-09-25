# Vivado XSim batch runner for the riskyC1-MC test suite.
#
#   cd <repo root>
#   vivado -mode batch -source sim/run_vivado.tcl -tclargs 32
#   vivado -mode batch -source sim/run_vivado.tcl -tclargs 16
#
# NREGS defaults to 32. Results print to the console and to sim/results.log.

set NREGS 32
if {$argc > 0} { set NREGS [lindex $argv 0] }

set root [pwd]
set src [list \
    $root/rtl/core_mc.sv \
    $root/rtl/decoder.sv \
    $root/rtl/imm_gen.sv \
    $root/rtl/mem_access.sv \
    $root/rtl/alu.sv \
    $root/rtl/register_file.sv \
    $root/tb/core_mc_tb.sv ]

file mkdir $root/sim/xsim_work
cd $root/sim/xsim_work

puts "== compiling (NREGS=$NREGS) =="
exec xvlog -sv {*}$src >@stdout
exec xelab -debug typical -generic_top "NREGS=$NREGS" core_mc_tb -s tb_snap >@stdout

set log [open $root/sim/results.log w]
set pass 0
set fail 0
foreach hex [lsort [glob $root/tests/*.hex]] {
    set name [file tail $hex]
    set out [exec xsim tb_snap -runall -testplusarg "HEX=$hex"]
    set line ""
    foreach l [split $out "\n"] {
        if {[string match "PASS*" $l] || [string match "FAIL*" $l] || [string match "TIMEOUT*" $l]} {
            set line $l
        }
    }
    puts $line
    puts $log $line
    if {[string match "PASS*" $line]} { incr pass } else { incr fail }
}
puts "------------------------------------------------"
puts "NREGS=$NREGS : $pass passed, $fail failed"
puts $log "NREGS=$NREGS : $pass passed, $fail failed"
close $log
cd $root
