#!perl

use strict;
use warnings;

use Test::More;


# Load extra tests.
eval
{
	require Test::CPAN::Changes;
};
plan( skip_all => 'Test::CPAN::Changes is required to check Changes file.' )
	if $@;

# Check the Changes file.
Test::CPAN::Changes::changes_ok();
