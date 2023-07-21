# SPDX-License-Identifier: GPL-2.0+

testutil_dep = declare_dependency(sources: ['testutils.c'])

tests = [
  'region_tree',
]

dl = cc.find_library('dl', required: false)

test_deps = [testutil_dep, util_dep, libfdt_extra_dep]
if not static_build
  test_deps += [dl]
endif

foreach t: tests
  executable(t, files(t + '.c'), dependencies: test_deps, link_args: extra_link_args)
endforeach

dtc = find_program('dtc')

dts_src = ['@SOURCE_ROOT@/tests/grep.dts']

dtbs = custom_target(
   'dtbs',
   command: [dtc, dts_src, '-o', 'grep.dtb'],
   output: ['grep.dtb'],
   )

run_tests = find_program('run_tests.sh')

test(
  'run-test',
  run_tests,
  workdir: meson.current_build_dir(),
  depends: dtbs,
  timeout: 1800, # mostly for valgrind
)
