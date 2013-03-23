#!perl

use strict;
use warnings;

use Test::More;


# Only test Kwalitee if we're doing release tests, not regular installation
# tests.
plan( skip_all => 'Author tests not required for installation.' )
	unless $ENV{'RELEASE_TESTING'};

# Load extra tests.
eval
{
	require Test::Kwalitee::Extra;
};
plan( skip_all => 'Test::Kwalitee required to evaluate code' )
	if $@;

# Run extra tests.
Test::Kwalitee::Extra->import(
	qw(
		!has_example
	)
);

# Clean up the extra file Test::Kwalitee generates.
END
{
	unlink 'Debian_CPANTS.txt'
		if -e 'Debian_CPANTS.txt';
}
