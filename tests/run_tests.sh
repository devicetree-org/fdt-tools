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
    echo -n "$1:	"
    if [ "$2" == "$3" ]; then
	PASS
    else
	FAIL "$2 != $3"
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
    TESTSETS="libfdt_extra"
fi

# Make sure we don't have stale blobs lying around
rm -f *.test.dtb *.test.dts

for set in $TESTSETS; do
    case $set in
	"libfdt_extra")
	    libfdt_extra_tests
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
