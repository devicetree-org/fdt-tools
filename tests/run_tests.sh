#!/bin/sh
# SPDX-License-Identifier: GPL-2.0+

SRCDIR=`dirname "$0"`
. "${SRCDIR}/./testutils.sh"

# Help things find the libfdt_extra shared object
if [ -z "$TEST_LIBDIR" ]; then
    TEST_LIBDIR=../libfdt_extra
fi
export LD_LIBRARY_PATH="$TEST_LIBDIR"

export QUIET_TEST=1

export VALGRIND=
VGCODE=126

tot_tests=0
tot_pass=0
tot_fail=0
tot_config=0
tot_vg=0
tot_strange=0

base_run_test() {
    tot_tests=$((tot_tests + 1))
    if VALGRIND="$VALGRIND" "$@"; then
	tot_pass=$((tot_pass + 1))
    else
	ret="$?"
	if [ "$ret" -eq 1 ]; then
	    tot_config=$((tot_config + 1))
	elif [ "$ret" -eq 2 ]; then
	    tot_fail=$((tot_fail + 1))
	elif [ "$ret" -eq $VGCODE ]; then
	    tot_vg=$((tot_vg + 1))
	else
	    tot_strange=$((tot_strange + 1))
	fi
    fi
}

shorten_echo () {
    limit=32
    echo -n "$1"
    shift
    for x; do
	if [ ${#x} -le $limit ]; then
	    echo -n " $x"
	else
	    short=$(echo "$x" | head -c$limit)
	    echo -n " \"$short\"...<${#x} bytes>"
	fi
    done
}

run_test () {
    echo -n "$@:	"
    if [ -n "$VALGRIND" -a -f $1.supp ]; then
	VGSUPP="--suppressions=$1.supp"
    fi
    base_run_test $VALGRIND $VGSUPP "./$@"
}

run_sh_test () {
    echo -n "$@:	"
    base_run_test sh "$@"
}

wrap_test () {
    (
	if verbose_run "$@"; then
	    PASS
	else
	    ret="$?"
	    if [ "$ret" -gt 127 ]; then
		signame=$(kill -l $((ret - 128)))
		FAIL "Killed by SIG$signame"
	    else
		FAIL "Returned error code $ret"
	    fi
	fi
    )
}

run_wrap_test () {
    shorten_echo "$@:	"
    base_run_test wrap_test "$@"
}

wrap_error () {
    (
	if verbose_run "$@"; then
	    FAIL "Expected non-zero return code"
	else
	    ret="$?"
	    if [ "$ret" -gt 127 ]; then
		signame=$(kill -l $((ret - 128)))
		FAIL "Killed by SIG$signame"
	    else
		PASS
	    fi
	fi
    )
}

run_wrap_error_test () {
    shorten_echo "$@"
    echo -n " {!= 0}:	"
    base_run_test wrap_error "$@"
}

run_dtc_test () {
    echo -n "dtc $@:	"
    base_run_test wrap_test $VALGRIND $DTC "$@"
}

# Add a property to a tree, then hash it and see if it changed
# Args:
#   $1: 0 if we expect it to stay the same, 1 if we expect a change
#   $2: node to add a property to
#   $3: arguments for fdtget
#   $4: filename of device tree binary
#   $5: hash of unchanged file (empty to calculate it)
#   $6: node to add a property to ("testing" by default if empty)
check_hash () {
    local changed="$1"
    local node="$2"
    local args="$3"
    local tree="$4"
    local base="$5"
    local nodename="$6"

    if [ -z "$nodename" ]; then
	nodename=testing
    fi
    if [ -z "$base" ]; then
	base=$($DTGREP ${args} -O bin $tree | sha1sum)
    fi
    $DTPUT $tree $node $nodename 1
    hash=$($DTGREP ${args} -O bin $tree | sha1sum)
    if [ "$base" == "$hash" ]; then
	if [ "$changed" == 1 ]; then
	    echo "$test: Hash should have changed"
	    echo base $base
	    echo hash $hash
	    false
	fi
    else
	if [ "$changed" == 0 ]; then
	    echo "$test: Base hash is $base but it was changed to $hash"
	    false
	fi
    fi
}

# Check the number of lines generated matches what we expect
# Args:
#   $1: Expected number of lines
#   $2...: Command line to run to generate output
check_lines () {
    local base="$1"

    shift
    lines=$($@ | wc -l)
    if [ "$base" != "$lines" ]; then
	echo "Expected $base lines but got $lines lines"
	false
    fi
}

# Check the number of bytes generated matches what we expect
# Args:
#   $1: Expected number of bytes
#   $2...: Command line to run to generate output
check_bytes () {
    local base="$1"

    shift
    bytes=$($@ | wc -c)
    if [ "$base" != "$bytes" ]; then
	echo "Expected $base bytes but got $bytes bytes"
	false
    fi
}

# Check whether a command generates output which contains a string
# Args:
#   $1: 0 to expect the string to be absent, 1 to expect it to be present
#   $2: text to grep for
#   $3...: Command to execute
check_contains () {
    contains="$1"
    text="$2"

    shift 2
    if $@ | grep -q $text; then
	if [ $contains -ne 1 ]; then
	    echo "Did not expect to find $text in output"
	    false
	fi
    else
	if [ $contains -ne 0 ]; then
	    echo "Expected to find $text in output"
	    false
	fi
    fi
}

# Check that $2 and $3 are equal. $1 is the test name to display
equal_test () {
    if [ "$2" = "$3" ]; then
	true
    else
	false
    fi
}

libfdt_extra_tests () {
    tmp=/tmp/tests.$$
    orig=region_tree.test.dtb

    # Tests for fdt_find_regions()
    for flags in $(seq 0 15); do
	run_test region_tree ${flags}
    done
}

fdtgrep_tests () {
    local addr
    local all_lines        # Total source lines in .dts file
    local base
    local dt_start
    local lines
    local node_lines       # Number of lines of 'struct' output
    local orig
    local string_size
    local tmp
    local tree

    tmp=/tmp/tests.$$
    orig=region_tree.test.dtb

    run_wrap_test ./region_tree 0 1000 ${orig}

    # Hash of partial tree
    # - modify tree in various ways and check that hash is unaffected
    tree=region_tree.mod.dtb
    cp $orig $tree
    args="-n /images/kernel@1"
    run_wrap_test check_hash 0 /images "$args" $tree
    run_wrap_test check_hash 0 /images/kernel@1/hash@1 "$args" $tree
    run_wrap_test check_hash 0 / "$args" $tree
    $DTPUT -c $tree /images/kernel@1/newnode
    run_wrap_test check_hash 0 / "$args" $tree
    run_wrap_test check_hash 1 /images/kernel@1 "$args" $tree

    # Now hash immediate subnodes so we detect a new subnode added
    cp $orig $tree
    args="-n /images/kernel@1 -e"
    run_wrap_test check_hash 0 /images "$args" $tree
    run_wrap_test check_hash 0 /images/kernel@1/hash@1 "$args" $tree
    run_wrap_test check_hash 0 / "$args" $tree
    base=$($DTGREP $args -O bin $tree | sha1sum)
    $DTPUT -c $tree /images/kernel@1/newnode
    run_wrap_test check_hash 1 / "$args" $tree "$base"
    cp $orig $tree
    run_wrap_test check_hash 1 /images/kernel@1 "$args" $tree

    # Hash the string table, which should change if we add a new property name
    # (Adding an existing property name will just reuse that string)
    cp $orig $tree
    args="-t -n /images/kernel@1"
    run_wrap_test check_hash 0 /images "$args" $tree "" data
    run_wrap_test check_hash 1 /images/kernel@1 "$args" $tree

    dts=${SRCDIR}/grep.dts
    dtb=grep.dtb
    run_dtc_test -O dtb -p 0x1000 -o $dtb $dts

    # Tests for each argument are roughly in alphabetical order
    #
    # First a sanity check that we can get back the source from the .dtb
    all_lines=$(cat $dts | wc -l)
    non_license_lines=$(($all_lines - 2))
    run_wrap_test check_lines ${non_license_lines} $DTGREP -Im $dtb
    node_lines=$(($non_license_lines - 2))

    # Get the offset of the dt_struct start (also tests -H somewhat)
    dt_start=$($DTGREP -H $dtb | awk '/off_dt_struct:/ {print $3}')
    dt_size=$($DTGREP -H $dtb | awk '/size_dt_struct:/ {print $3}')

    # Check -a: the first line should contain the offset of the dt_start
    addr=$($DTGREP -a $dtb | head -1 | tr -d : | awk '{print $1}')
    run_wrap_test equal_test "-a offset first" "$dt_start" "0x$addr"

    # Last line should be 8 bytes less than the size (NODE, END tags)
    addr=$($DTGREP -a $dtb | tail -1 | tr -d : | awk '{print $1}')
    last=$(printf "%#x" $(($dt_start + $dt_size - 8)))
    run_wrap_test equal_test "-a offset last" "$last" "0x$addr"

    # Check the offset option in a similar way. The first offset should be 0
    # and the last one should be the size of the struct area.
    addr=$($DTGREP -f $dtb | head -1 | tr -d : | awk '{print $1}')
    run_wrap_test equal_test "-o offset first" "0x0" "0x$addr"
    addr=$($DTGREP -f $dtb | tail -1 | tr -d : | awk '{print $1}')
    last=$(printf "%#x" $(($dt_size - 8)))
    run_wrap_test equal_test "-f offset last" "$last" "0x$addr"

    # Check that -A controls display of all lines
    # The 'chosen' node should only have four output lines
    run_wrap_test check_lines $node_lines $DTGREP -S -A -n /chosen $dtb
    run_wrap_test check_lines 4 $DTGREP -S -n /chosen $dtb

    # Check that -c picks out nodes
    run_wrap_test check_lines 7 $DTGREP -S -c ixtapa $dtb
    run_wrap_test check_lines $(($node_lines - 7)) $DTGREP -S -C ixtapa $dtb

    # -d marks selected lines with +
    run_wrap_test check_lines $node_lines $DTGREP -S -Ad -n /chosen $dtb
    run_wrap_test check_lines 4 $DTGREP -S -Ad -n /chosen $dtb |grep +

    # -g should find a node, property or compatible string
    run_wrap_test check_lines 2 $DTGREP -S -g / $dtb
    run_wrap_test check_lines 2 $DTGREP -S -g /chosen $dtb
    run_wrap_test check_lines $(($node_lines - 2)) $DTGREP -S -G /chosen $dtb

    run_wrap_test check_lines 1 $DTGREP -S -g bootargs $dtb
    run_wrap_test check_lines $(($node_lines - 1)) $DTGREP -S -G bootargs $dtb

    # We should find the /holiday node, so 1 line for 'holiday {', one for '}'
    run_wrap_test check_lines 2 $DTGREP -S -g ixtapa $dtb
    run_wrap_test check_lines $(($node_lines - 2)) $DTGREP -S -G ixtapa $dtb

    run_wrap_test check_lines 3 $DTGREP -S -g ixtapa -g bootargs $dtb
    run_wrap_test check_lines $(($node_lines - 3)) $DTGREP -S -G ixtapa \
	-G bootargs $dtb

    # -l outputs a,list of regions - here we should get 3: one for the header,
    # one for the node and one for the 'end' tag.
    run_wrap_test check_lines 3 $DTGREP -S -l -n /chosen $dtb -o $tmp

    # -L outputs all the strings in the string table
    cat >$tmp <<END
	#address-cells
	airline
	bootargs
	compatible
	linux,platform
	model
	reg
	#size-cells
	status
	weather
END
    lines=$(cat $tmp | wc -l)
    run_wrap_test check_lines $lines $DTGREP -S -L -n // $dtb

    # Check that the -m flag works
    run_wrap_test check_contains 1 memreserve $DTGREP -Im $dtb
    run_wrap_test check_contains 0 memreserve $DTGREP -I $dtb

    # Test -n
    run_wrap_test check_lines 0 $DTGREP -S -n // $dtb
    run_wrap_test check_lines 0 $DTGREP -S -n chosen $dtb
    run_wrap_test check_lines 0 $DTGREP -S -n holiday $dtb
    run_wrap_test check_lines 0 $DTGREP -S -n \"\" $dtb
    run_wrap_test check_lines 4 $DTGREP -S -n /chosen $dtb
    run_wrap_test check_lines 7 $DTGREP -S -n /holiday $dtb
    run_wrap_test check_lines 11 $DTGREP -S -n /chosen -n /holiday $dtb

    # Test -N which should list everything except matching nodes
    run_wrap_test check_lines $node_lines $DTGREP -S -N // $dtb
    run_wrap_test check_lines $node_lines $DTGREP -S -N chosen $dtb
    run_wrap_test check_lines $(($node_lines - 4)) $DTGREP -S -N /chosen $dtb
    run_wrap_test check_lines $(($node_lines - 7)) $DTGREP -S -N /holiday $dtb
    run_wrap_test check_lines $(($node_lines - 11)) $DTGREP -S -N /chosen \
	-N /holiday $dtb

    # Using -n and -N together is undefined, so we don't have tests for that
    # The same applies for -p/-P and -c/-C.
    run_wrap_error_test $DTGREP -n chosen -N holiday $dtb
    run_wrap_error_test $DTGREP -c chosen -C holiday $dtb
    run_wrap_error_test $DTGREP -p chosen -P holiday $dtb

    # Test -o: this should output just the .dts file to a file
    # Where there is non-dts output it should go to stdout
    rm -f $tmp
    run_wrap_test check_lines 0 $DTGREP $dtb -o $tmp
    run_wrap_test check_lines $node_lines cat $tmp

    # Here we expect a region list with a single entry, plus a header line
    # on stdout
    run_wrap_test check_lines 2 $DTGREP $dtb -o $tmp -l
    run_wrap_test check_lines $node_lines cat $tmp

    # Here we expect a list of strings on stdout
    run_wrap_test check_lines ${lines} $DTGREP $dtb -o $tmp -L
    run_wrap_test check_lines $node_lines cat $tmp

    # Test -p: with -S we only get the compatible lines themselves
    run_wrap_test check_lines 2 $DTGREP -S -p compatible -n // $dtb
    run_wrap_test check_lines 1 $DTGREP -S -p bootargs -n // $dtb

    # Without -S we also get the node containing these properties
    run_wrap_test check_lines 6 $DTGREP -p compatible -n // $dtb
    run_wrap_test check_lines 5 $DTGREP -p bootargs -n // $dtb

    # Now similar tests for -P
    # First get the number of property lines (containing '=')
    lines=$(grep "=" $dts |wc -l)
    run_wrap_test check_lines $(($lines - 2)) $DTGREP -S -P compatible \
	-n // $dtb
    run_wrap_test check_lines $(($lines - 1)) $DTGREP -S -P bootargs \
	-n // $dtb
    run_wrap_test check_lines $(($lines - 3)) $DTGREP -S -P compatible \
	-P bootargs -n // $dtb

    # Without -S we also get the node containing these properties
    run_wrap_test check_lines $(($node_lines - 2)) $DTGREP -P compatible \
	-n // $dtb
    run_wrap_test check_lines $(($node_lines - 1)) $DTGREP -P bootargs \
	-n // $dtb
    run_wrap_test check_lines $(($node_lines - 3)) $DTGREP -P compatible \
	-P bootargs -n // $dtb

    # -s should bring in all sub-nodes
    run_wrap_test check_lines 2 $DTGREP -p none -n / $dtb
    run_wrap_test check_lines 6 $DTGREP -e -p none -n / $dtb
    run_wrap_test check_lines 2 $DTGREP -S -p none -n /holiday $dtb
    run_wrap_test check_lines 4 $DTGREP  -p none -n /holiday $dtb
    run_wrap_test check_lines 8 $DTGREP -e -p none -n /holiday $dtb

    # check -b with and without -u
    run_wrap_test check_lines 12 $DTGREP -b airline $dtb
    run_wrap_test check_lines 21 $DTGREP -u -b airline $dtb
    run_wrap_test check_lines 6 $DTGREP -b bootargs $dtb
    run_wrap_test check_lines 10 $DTGREP -u -b bootargs $dtb

    # -v inverts the polarity of any condition
    run_wrap_test check_lines $(($node_lines - 2)) $DTGREP -Sv -p none \
	-n / $dtb
    run_wrap_test check_lines $(($node_lines - 2)) $DTGREP -Sv -p compatible \
	-n // $dtb
    run_wrap_test check_lines $(($node_lines - 2)) $DTGREP -Sv -g /chosen \
	$dtb
    run_wrap_test check_lines $node_lines $DTGREP -Sv -n // $dtb
    run_wrap_test check_lines $node_lines $DTGREP -Sv -n chosen $dtb
    run_wrap_error_test $DTGREP -v -N holiday $dtb

    # Check that the -I flag works
    run_wrap_test check_contains 1 dts-v1 $DTGREP -I $dtb
    run_wrap_test check_contains 0 dts-v1 $DTGREP $dtb

    # Now some dtb tests. The dts tests above have tested the basic grepping
    # features so we only need to concern ourselves with things that are
    # different about dtb/bin output.

    # An empty node list should just give us the FDT_END tag
    run_wrap_test check_bytes 4 $DTGREP -n // -S -O bin $dtb

    # The mem_rsvmap is two entries of 16 bytes each
    run_wrap_test check_bytes $((4 + 32)) $DTGREP -m -n // -S -O bin $dtb

    # Check we can add the string table
    string_size=$($DTGREP -H $dtb | awk '/size_dt_strings:/ {print $3}')
    run_wrap_test check_bytes $((4 + $string_size)) $DTGREP -t -n // -O bin -S \
	$dtb
    run_wrap_test check_bytes $((4 + 32 + $string_size)) $DTGREP -tm \
	-n // -S -O bin $dtb

    # Check that a pass-through works ok. fdtgrep aligns the mem_rsvmap table
    # to a 16-bytes boundary, but dtc uses 8 bytes so we expect the size to
    # increase by 8 bytes...
    run_dtc_test -O dtb -o $dtb $dts
    base=$(stat -c %s $dtb)
    run_wrap_test check_bytes $base $DTGREP -O dtb $dtb

    # ...but we should get the same output from fdtgrep in a second pass
    run_wrap_test check_bytes 0 $DTGREP -O dtb $dtb -o $tmp
    base=$(stat -c %s $tmp)
    run_wrap_test check_bytes $base $DTGREP -O dtb $tmp

    rm -f $tmp
}

while getopts "vt:m" ARG ; do
    case $ARG in
	"v")
	    unset QUIET_TEST
	    ;;
	"t")
	    TESTSETS=$OPTARG
	    ;;
	"m")
	    VALGRIND="valgrind --tool=memcheck -q --error-exitcode=$VGCODE"
	    ;;
    esac
done

if [ -z "$TESTSETS" ]; then
    TESTSETS="libfdt_extra fdtgrep"
fi

# Make sure we don't have stale blobs lying around
rm -f *.test.dtb *.test.dts

for set in $TESTSETS; do
    case $set in
	"libfdt_extra")
	    libfdt_extra_tests
	    ;;
	"fdtgrep")
	    fdtgrep_tests
	    ;;
    esac
done

echo "********** TEST SUMMARY"
echo "*     Total testcases:	$tot_tests"
echo "*                PASS:	$tot_pass"
echo "*                FAIL:	$tot_fail"
echo "*   Bad configuration:	$tot_config"
if [ -n "$VALGRIND" ]; then
    echo "*    valgrind errors:	$tot_vg"
fi
echo "* Strange test result:	$tot_strange"
echo "**********"
