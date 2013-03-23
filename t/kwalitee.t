#!perl

use strict;
use warnings;

use Test::More;


# Only test Kwalitee if were doing release tests, not regular installation
# tests.
plan( skip_all => 'Author tests not required for installation.' )
	unless $ENV{'RELEASE_TESTING'};

# Load the Kwalitee tests.
eval
{
	require Test::Kwalitee;
};
plan( skip_all => 'Test::Kwalitee required to evaluate code' )
	if $@;

# Run Kwalitee tests.
Test::Kwalitee->import();
