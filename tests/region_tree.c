// SPDX-License-Identifier: GPL-2.0+
/*
 * hash_tree - Testcase for fdt_find_regions()
 *
 * Copyright 2023 Google LLC
 */

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libfdt_env.h>
#include <fdt.h>
#include <libfdt.h>

#include "fdt_region.h"

#include "tests.h"
#include "testdata.h"

#define SPACE	65536

#define CHECK(code) \
	{ \
		err = (code); \
		if (err) \
			FAIL(#code ": %s", fdt_strerror(err)); \
	}

/*
 * Regions we expect to see returned from fdt_find_regions(). We build up a
 * list of these as we make the tree, then check the results of
 * fdt_find_regions() once we are done.
 */
static struct fdt_region expect[20];

/* Number of expected regions */
int expect_count;

/* Mark the start of a new region */
static void start(void *fdt)
{
	expect[expect_count].offset = fdt_size_dt_struct(fdt);
	verbose_printf("[%d: %x ", expect_count,
	       fdt_off_dt_struct(fdt) + expect[expect_count].offset);
}

/* Mark the end of a region */
static void stop(void *fdt)
{
	expect[expect_count].size = fdt_size_dt_struct(fdt) -
			expect[expect_count].offset;
	expect[expect_count].offset += fdt_off_dt_struct(fdt);
	verbose_printf("%x]\n", expect[expect_count].offset +
			expect[expect_count].size);
	expect_count++;
}

/**
 * build_tree() - Build a tree
 *
 * @fdt:	Pointer to place to put tree, assumed to be large enough
 * @flags:	Flags to control the tree creation (FDT_REG_...)
 * @space:	Amount of space to create for later tree additions
 *
 * This creates a tree modelled on a U-Boot FIT image, with various nodes
 * and properties which are useful for testing the hashing features of
 * fdt_find_regions().
 *
 * See h_include() below for a list of the nodes we later search for.
 */
static void build_tree(void *fdt, int flags, int space)
{
	int direct_subnodes = flags & FDT_REG_DIRECT_SUBNODES;
	int all_subnodes = flags & FDT_REG_ALL_SUBNODES;
	int supernodes = flags & FDT_REG_SUPERNODES;
	int either = !all_subnodes && (direct_subnodes || supernodes);
	int err;

	CHECK(fdt_create(fdt, SPACE));

	CHECK(fdt_add_reservemap_entry(fdt, TEST_ADDR_1, TEST_SIZE_1));
	CHECK(fdt_add_reservemap_entry(fdt, TEST_ADDR_2, TEST_SIZE_2));
	CHECK(fdt_finish_reservemap(fdt));

	/*
	 * This is the start of a new region because in the fdt_xxx_region()
	 * call, we pass "/" as one of the nodes to find.
	 */
	start(fdt);	/* region 0 */
	CHECK(fdt_begin_node(fdt, ""));
	CHECK(fdt_property_string(fdt, "description", "kernel image"));
	CHECK(fdt_property_u32(fdt, "#address-cells", 1));

	/* /images */
	if (!either && !all_subnodes)
		stop(fdt);
	CHECK(fdt_begin_node(fdt, "images"));
	if (either)
		stop(fdt);
	CHECK(fdt_property_u32(fdt, "image-prop", 1));

	/* /images/kernel@1 */
	if (!all_subnodes)
		start(fdt);	/* region 1 */
	CHECK(fdt_begin_node(fdt, "kernel@1"));
	CHECK(fdt_property_string(fdt, "description", "exynos kernel"));
	stop(fdt);
	CHECK(fdt_property_string(fdt, "data", "this is the kernel image"));
	start(fdt);	/* region 2 */

	/* /images/kernel/hash@1 */
	CHECK(fdt_begin_node(fdt, "hash@1"));
	CHECK(fdt_property_string(fdt, "algo", "sha1"));
	CHECK(fdt_end_node(fdt));

	/* /images/kernel/hash@2 */
	if (!direct_subnodes)
		stop(fdt);
	CHECK(fdt_begin_node(fdt, "hash@2"));
	if (direct_subnodes)
		stop(fdt);
	CHECK(fdt_property_string(fdt, "algo", "sha1"));
	if (direct_subnodes)
		start(fdt);	/* region 3 */
	CHECK(fdt_end_node(fdt));
	if (!direct_subnodes)
		start(fdt);	/* region 3 */

	CHECK(fdt_end_node(fdt));

	/* /images/fdt@1 */
	CHECK(fdt_begin_node(fdt, "fdt@1"));
	CHECK(fdt_property_string(fdt, "description", "snow FDT"));
	if (!all_subnodes)
		stop(fdt);
	CHECK(fdt_property_string(fdt, "data", "FDT data"));
	if (!all_subnodes)
		start(fdt);	/* region 4 */

	/* /images/kernel/hash@1 */
	CHECK(fdt_begin_node(fdt, "hash@1"));
	CHECK(fdt_property_string(fdt, "algo", "sha1"));
	CHECK(fdt_end_node(fdt));

	CHECK(fdt_end_node(fdt));

	if (!either && !all_subnodes)
		stop(fdt);
	CHECK(fdt_end_node(fdt));

	/* /configurations */
	CHECK(fdt_begin_node(fdt, "configurations"));
	if (either)
		stop(fdt);
	CHECK(fdt_property_string(fdt, "default", "conf@1"));

	/* /configurations/conf@1 */
	if (!all_subnodes)
		start(fdt);	/* region 6 */
	CHECK(fdt_begin_node(fdt, "conf@1"));
	CHECK(fdt_property_string(fdt, "kernel", "kernel@1"));
	CHECK(fdt_property_string(fdt, "fdt", "fdt@1"));
	CHECK(fdt_end_node(fdt));
	if (!all_subnodes)
		stop(fdt);

	/* /configurations/conf@2 */
	CHECK(fdt_begin_node(fdt, "conf@2"));
	CHECK(fdt_property_string(fdt, "kernel", "kernel@1"));
	CHECK(fdt_property_string(fdt, "fdt", "fdt@2"));
	CHECK(fdt_end_node(fdt));

	if (either)
		start(fdt);	/* region 7 */
	CHECK(fdt_end_node(fdt));
	if (!either && !all_subnodes)
		start(fdt);	/* region 7 */

	CHECK(fdt_end_node(fdt));

	CHECK(fdt_finish(fdt));
	stop(fdt);

	/* Add in the strings */
	if (flags & FDT_REG_ADD_STRING_TAB) {
		expect[expect_count].offset = fdt_off_dt_strings(fdt);
		expect[expect_count].size = fdt_size_dt_strings(fdt);
		expect_count++;
	}

	/* Make a bit of space */
	if (space)
		CHECK(fdt_open_into(fdt, fdt, fdt_totalsize(fdt) + space));

	verbose_printf("Completed tree, totalsize = %d\n", fdt_totalsize(fdt));
}

/**
 * strlist_contains() - Returns 1 if a string is contained in a list
 *
 * @list:	List of strings
 * @count:	Number of strings in list
 * @str:	String to search for
 */
static int strlist_contains(const char * const list[], int count,
			    const char *str)
{
	int i;

	for (i = 0; i < count; i++)
		if (!strcmp(list[i], str))
			return 1;

	return 0;
}

/**
 * h_include() - Our include handler for fdt_find_regions()
 *
 * This is very simple - we have a list of nodes we are looking for, and
 * one property that we want to exclude.
 */
static int h_include(void *priv, const void *fdt, int offset, int type,
		     const char *data, int size)
{
	const char * const inc[] = {
		"/",
		"/images/kernel@1",
		"/images/fdt@1",
		"/configurations/conf@1",
		"/images/kernel@1/hash@1",
		"/images/fdt@1/hash@1",
	};

	switch (type) {
	case FDT_IS_NODE:
		return strlist_contains(inc, 6, data);
	case FDT_IS_PROP:
		return !strcmp(data, "data") ? 0 : -1;
	}

	return 0;
}

/**
 * check_regions() - Check that the regions are as we expect
 *
 * Call fdt_find_regions() and check that the results are as we expect them,
 * matching the list of expected regions we created at the same time as
 * the tree.
 *
 * @fdt:	Pointer to device tree to check
 * @flags:	Flags value (FDT_REG_...)
 * @return 0 if ok, -1 on failure
 */
static int check_regions(const void *fdt, int flags)
{
	struct fdt_region_state state;
	struct fdt_region reg;
	int err, ret = 0;
	char path[1024];
	int count = 0;
	int i;

	ret = fdt_first_region(fdt, h_include, NULL, &reg,
			       path, sizeof(path), flags, &state);
	if (ret < 0)
		CHECK(ret);

	verbose_printf("Regions: %d\n", count);
	for (i = 0; ; i++) {
		struct fdt_region *exp = &expect[i];

		verbose_printf("%d:  %-10x  %-10x\n", i, reg.offset,
		       reg.offset + reg.size);
		if (memcmp(exp, &reg, sizeof(reg))) {
			ret = -1;
			verbose_printf("exp: %-10x  %-10x\n", exp->offset,
				exp->offset + exp->size);
		}

		ret = fdt_next_region(fdt, h_include, NULL, &reg,
				      path, sizeof(path), flags, &state);
		if (ret < 0) {
			if (ret == -FDT_ERR_NOTFOUND)
				ret = 0;
			CHECK(ret);
			i++;
			break;
		}
	}
	verbose_printf("expect_count = %d, i=%d\n", expect_count, i);
	if (expect_count != i)
		FAIL();

	return ret;
}

int main(int argc, char *argv[])
{
	const char *fname = NULL;
	int flags = 0;
	int space = 0;
	void *fdt;

	test_init(argc, argv);
	if (argc < 2) {
		verbose_printf("Usage: %s <flag value> [<space>] [<output_fname.dtb>]",
			       argv[0]);
		FAIL();
	}
	flags = atoi(argv[1]);
	if (argc >= 3)
		space = atoi(argv[2]);
	if (argc >= 4)
		fname = argv[3];

	/*
	 * Allocate space for the tree and build it, creating a list of
	 * expected regions.
	 */
	fdt = xmalloc(SPACE);
	build_tree(fdt, flags, space);

	/* Write the tree out if required */
	if (fname)
		save_blob(fname, fdt);

	/* Check the regions are what we expect */
	if (check_regions(fdt, flags))
		FAIL();
	else
		PASS();

	return 0;
}
