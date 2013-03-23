#!perl -T

use strict;
use warnings;

use Test::More;


# Only test this if we're doing release tests, not regular installation tests.
plan( skip_all => 'Author tests not required for installation.' )
	unless $ENV{'RELEASE_TESTING'};

# Load Test::Pod.
my $min_version = '1.22';
eval "use Test::Pod $min_version";
plan( skip_all => "Test::Pod $min_version required." )
	if $@;

# Check POD.
all_pod_files_ok();
