#!perl -T

use strict;
use warnings;

use File::Spec;
use Test::More;

 
# Only test this if we're doing release tests, not regular installation tests.
plan( skip_all => 'Author tests not required for installation.' )
	unless $ENV{'RELEASE_TESTING'};

# Load Test::Perl::Critic.
eval
{
	require Test::Perl::Critic;
};
plan( skip_all => 'Test::Perl::Critic required.' )
	if $@;

# Run PerlCritic.
Test::Perl::Critic->import( -profile => '.perlcriticrc' );
all_critic_ok();
