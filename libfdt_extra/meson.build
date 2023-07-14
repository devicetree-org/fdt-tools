# SPDX-License-Identifier: GPL-2.0+

version_script = '-Wl,--version-script=@0@'.format(meson.current_source_dir() / 'version.lds')
if not cc.has_link_argument(version_script)
  version_script = []
endif

sources = files(
  'fdt_region.c',
)

link_args = []
if cc.has_link_argument('-Wl,--no-undefined')
    link_args += '-Wl,--no-undefined'
else
    # -undefined error is the equivalent of --no-undefined for the macOS linker,
    # but -undefined would also be understood as a valid argument for GNU ld!
    link_args += cc.get_supported_link_arguments('-Wl,-undefined,error')
endif

link_args += version_script
libfdt_extra = library(
  'fdt_extra', sources,
  version: '1.6.0',
  dependencies: libfdt_dep,
  link_args: link_args,
  link_depends: 'version.lds',
  install: true,
)

libfdt_extra_a = static_library(
  'fdt_extra', sources,
  dependencies: libfdt_dep,
  install: true,
)

libfdt_extra_inc = include_directories('.')

if static_build
  link_with = libfdt_extra_a
else
  link_with = libfdt_extra
endif

libfdt_extra_dep = declare_dependency(
  include_directories: libfdt_extra_inc,
  dependencies: libfdt_dep,
  link_with: link_with,
)

install_headers(
  files(
    'fdt_region.h',
  )
)

pkgconfig = import('pkgconfig')

pkgconfig.generate(
  libraries: libfdt_extra,
  version: meson.project_version(),
  filebase: 'libfdt_extra',
  name: 'libfdt_extra',
  description: 'Flat Device Tree extra features',
)
