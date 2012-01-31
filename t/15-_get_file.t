#!perl

# Note: cannot use -T here, Git::Repository uses environment variables directly.

use strict;
use warnings;

use Perl::Critic::Git;
use Test::Exception;
use Test::Git;
use Test::More;


# Check there is a git binary available, or skip all.
has_git();
plan( tests => 4 );

# Retrieve the path to the test git repository.
ok(
	open( my $persistent, '<', 't/test_information' ),
	'Retrieve the persistent test information.',
) || diag( "Error: $!" );
ok(
	defined( my $work_tree = <$persistent> ),
	'Retrieve the path to the test git repository.',
);

# Prepare Perl::Critic::Git.
my $file = $work_tree . '/test.pl';
my $git_critic;
lives_ok(
	sub
	{
		$git_critic = Perl::Critic::Git->new(
			file   => $file,
			level  => 'harsh',
		);
	},
	'Create a Perl::Critic::Git object.',
);

is(
	$git_critic->_get_file(),
	$file,
	'Retrieve the path to the file set with new().',
);
