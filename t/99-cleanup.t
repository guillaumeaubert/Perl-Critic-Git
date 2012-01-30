#!perl

# Note: cannot use -T here, Git::Repository uses environment variables directly.

use strict;
use warnings;

use File::Path qw();
use Test::Exception;
use Test::More tests => 6;


# Retrieve the path to the test git repository.
ok(
	open( my $persistent, '<', 't/test_information' ),
	'Retrieve the persistent test information.',
) || diag( "Error: $!" );
ok(
	defined( my $work_tree = <$persistent> ),
	'Retrieve the path to the test git repository.',
);

SKIP:
{
	skip(
		'The git directory has already been removed.',
		2,
	) unless -e $work_tree;
	
	lives_ok(
		sub
		{
			File::Path::rmtree( $work_tree );
		},
		'Remove the temporary test git directory.',
	);
	
	ok(
		! -e $work_tree,
		'The temporary test git directory does not exist anymore.',
	);
}

my $test_information = 't/test_information';
SKIP:
{
	skip(
		'The temporary test information file has already been removed.',
		2,
	) unless -e $test_information;
	
	lives_ok(
		sub
		{
			unlink( $test_information ) || die "Failed to remove file: $!";
		},
		'Remove the test information file.',
	);
	
	ok(
		! -e $test_information,
		'The test information file does not exist anymore.',
	);
}