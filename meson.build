# SPDX-License-Identifier: GPL-2.0+

project('fdt-tools', 'c',
  version: '1.7.0',
  license: ['GPL2+', 'BSD-2'],
  default_options: 'werror=true',
)

cc = meson.get_compiler('c')

add_project_arguments(
  cc.get_supported_arguments([
    '-Wpointer-arith',
    '-Wcast-qual',
    '-Wnested-externs',
    '-Wstrict-prototypes',
    '-Wmissing-prototypes',
    '-Wredundant-decls',
    '-Wshadow',
    '-Wsuggest-attribute=format',
    '-Wwrite-strings',
  ]),
  language: 'c'
)

if host_machine.system() == 'windows'
  add_project_arguments(
    '-D__USE_MINGW_ANSI_STDIO=1',
    language: 'c'
  )
endif

if get_option('static-build')
  static_build = true
  extra_link_args = ['-static']
else
  static_build = false
  extra_link_args = []
endif

valgrind = dependency('valgrind', required: get_option('valgrind'))
if not valgrind.found()
  add_project_arguments('-DNO_VALGRIND', language: 'c')
endif

version_gen_h = vcs_tag(
  input: 'version_gen.h.in',
  output: 'version_gen.h',
)

libfdt_dep = cc.find_library('fdt')

subdir('libfdt_extra')

if get_option('tools')
  util_dep = declare_dependency(
    sources: ['util.c', version_gen_h],
    include_directories: '.',
    dependencies: libfdt_extra_dep
  )

  foreach e: ['fdtgrep']
    executable(e, files(e + '.c'),
               dependencies: [util_dep, libfdt_dep],
               install: true,
               link_args: extra_link_args)
  endforeach
endif

if not meson.is_cross_build()
  if get_option('tools')
    subdir('tests')
  endif
endif
