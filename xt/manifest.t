#!perl -T

use strict;
use warnings;

use Test::More;


# Only test this if we're doing release tests, not regular installation tests.
plan( skip_all => 'Author tests not required for installation.' )
	unless $ENV{'RELEASE_TESTING'};

# Load Test::CheckManifest.
my $min_version = '0.9';
eval "use Test::CheckManifest $min_version";
plan( skip_all => "Test::CheckManifest $min_version required" )
	if $@;

# Verify files against manifest.
ok_manifest(
	{
		exclude => [ '/.git/' ],
	}
);
