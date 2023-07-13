# Flattened Device Tree (FDT) tools

This contains tools for use with FDT.

## FDT Regions

This feature adds two new functions, fdt_first_region() and
fdt_next_regions() which map FDT parts such as nodes and properties to
their regions in the FDT binary. The function is then used to implement
a grep utility for FDTs.

The core code is quite simple and small, but it grew a little due
to the need to make it iterative (first/next/next). Also this series adds
tests and a grep utility, so quite a bit of code is built on it.

The use for this feature is twofold. Firstly it provides a convenient
way of performing a structure-aware grep of the tree. For example it is
possible to grep for a node and get all the properties associated with
that node. Trees can be subsetted easily, by specifying the nodes that
are required, and then writing out the regions returned by this function.
This is useful for small resource-constrained systems, such as boot
loaders, which want to use an FDT but do not need to know about all of
it. The full FDT can be grepped to pull out the few things that are
needed - this can be an automatic part of the build system and does
not require the FDT source code.

This first use makes it easy to implement an FDT grep. Options are
provided to search for matching nodes (by name or compatible string),
properties and also for any of the above. It is possible to search for
non-matches also (useful for excluding a particular property from the
FDT, for example). The output is like fdtdump, but only with the regions
selected by the grep. Options are also provided to print the string table,
memory reservation table, etc. The fdtgrep utility can output valid
source, which can be used by dtc, but it can also directly output a new
.dtb binary.

Secondly it makes it easy to hash parts of the tree and detect changes.
The intent is to get a list of regions which will be invariant provided
those parts are invariant. For example, if you request a list of regions
for all nodes but exclude the property "data", then you will get the
same region contents regardless of any change to "data" properties.
An assumption is made here that the tree ordering remains the same.

This second use is the subject of a recent series sent to the U-Boot
mailing list, to enhance FIT images to support verified boot. Briefly,
this works by signing configurations (consisting of particular kernel
and FDT combinations) so that the boot loader can verify that these
combinations are valid and permitted. Since a FIT image is in fact an
FDT, we need to be able to hash particular regions of the FDT for the
signing and verification process. This is done by using the region functions
to select the data that needs to be hashed for a particular configuration.

The fdtgrep utility could be used to replace all of the functions of
fdtdump. However fdtdump is intended as a separate, simple way of
dumping the tree (for verifying against dtc output for example). So
fdtdump remains a separate program and this series leaves it alone.

Note: a somewhat unfortunately feature of this implementation is that
a state structure needs to be kept around between calls of
fdt_next_region(). This is declared in libfdt.h but really should be
opaque.


## fdtgrep -- Extract portions of a Device Tree and output them

The fdtgrep program allows you to 'grep' a Device Tree file in a structured
way. The output of fdtgrep is either another Device Tree file or a text file,
perhaps with some pieces omitted.

This is useful in a few situations:

    - Finding a node or property in a device tree and displaying it along
      with its surrounding context. This is helpful since some files are
      quite large.
    - Creating a smaller device tree which omits some portions. For example
      a full Linux kernel device tree may be cut down for use by a simple
      boot loader (perhaps removing the pinmux information).

The syntax of the fdtgrep commandline is described in the help (fdtgrep -h)
and there are many options. Some common uses are as follows:

    fdtgrep -s -n /node <DTB-file-name>
        - Output just a node and its subnodes

    fdtgrep -s -n /node -o out.dtb -O dtb <DTB-file-name>
        - Same but output as a binary Device Tree

    fdtgrep -s -N /node <DTB-file-name>
        - Output everything except the given node

    fdtgrep -a -n /compatible -n /aliases <DTB-file-name>
        - Output compatible and alias nodes

    fdtgrep -s /node -O bin <DTB-file-name> | sha1sum
        - Take the sha1sum of just the portion of the Device Tree occupied
          by the /node node. This could be compared with the same node from
          another file perhaps, to see if they match.
        - You can add -tme to produce a valid Device Tree including header,
          memreserve table and string table.

    fdtgrep -A /node <DTB-file-name>
        - Output just a node and its subnodes

    fdtgrep -f /chosen spi4 <DTB-file-name>
        - Output nodes/properties/compatibles strings which match /chosen and
          spi4. Add the hex offset on the left of each. Note that -g is the
          default parameter type, so this equivalent to:
               fdtgrep -f -g /chosen -g spi4 <DTB-file-name>

    fdtgrep -a /chosen spi4 <DTB-file-name>
        - Similar but use absolute file offset. This allows finding nodes
          and properties in a file with a hex dumper.

    fdtgrep -a /chosen spi4 <DTB-file-name>
        - Similar but use absolute file offset. This allows finding nodes
          and properties in a file with a hex dumper.

    fdtgrep -A /chosen spi4 <DTB-file-name>
        - Output everything, but colour the nodes and properties which match
          /chosen and spi4 green, and everything else red.

    fdtgrep -Ad /chosen spi4 <DTB-file-name>
        - Similar but use + and - to indicate included and excluded lines.

    fdtgrep -Adv /chosen spi4 <DTB-file-name>
        - Invert the above (-v operates similarly to -v with standard grep)

    fdtgrep -c google,cros-ec-keyb <DTB-file-name>
        - Show the node with the given compatible string

    fdtgrep -n x -p compatible <DTB-file-name>
        - List all nodes and their compatible strings. The '-n x' drops all
          nodes not called 'x', which his all of them. If you want to list
          nodes without a compatible as well, then omit this.

Note you can use:
    -n/N to include/exclude nodes
    -p/N to include/exclude properties
    -c/C to include/exclude nodes which have a particular compatible string
    -g/G to include/exclude any of the above (global search)

    Note it is not permitted to use a positive/negative search of the same
    type at the same time. You can do this in two steps, such as:

       ./fdtgrep -n x -p compatible x -O dtb |./fdtgrep - -n /serial@12C10000

    but it is hard to see why this would be useful. Unfortunately fdtgrep
    does not support wildcard matching or regular expressions.
