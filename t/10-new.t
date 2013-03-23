#!perl

# Note: cannot use -T here, Git::Repository uses environment variables directly.

use strict;
use warnings;

use Perl::Critic::Git;
use Test::Exception;
use Test::Git;
use Test::More;
use Test::NoWarnings qw();


# Check there is a git binary available, or skip all.
has_git();
plan( tests => 9 );

# Retrieve the path to the test git repository.
ok(
	open( my $persistent, '<', 't/test_information' ),
	'Retrieve the persistent test information.',
) || diag( "Error: $!" );
ok(
	defined( my $work_tree = <$persistent> ),
	'Retrieve the path to the test git repository.',
);

# Make sure that the right parameters return a valid object.
my $git_critic;
lives_ok(
	sub
	{
		$git_critic = Perl::Critic::Git->new(
			file   => $work_tree . '/test.pl',
			level  => 'harsh',
		);
	},
	'Create an object with "file" and "level" set properly.',
);
isa_ok(
	$git_critic,
	'Perl::Critic::Git',
	'$git_critic',
);
lives_ok(
	sub
	{
		$git_critic = Perl::Critic::Git->new(
			file   => 'README',
		);
	},
	'Create an object without "level" to make sure it is optional.',
);

# Test error conditions.
dies_ok(
	sub
	{
		$git_critic = Perl::Critic::Git->new(
			level  => 'harsh',
		);
	},
	'"file" must be defined.',
);
dies_ok(
	sub
	{
		$git_critic = Perl::Critic::Git->new(
			file   => 'not_found',
			level  => 'harsh',
		);
	},
	'"file" must be a valid file path.'
);
dies_ok(
	sub
	{
		$git_critic = Perl::Critic::Git->new(
			file   => $work_tree . '/test.pl',
			level  => 'violent',
		);
	},
	'"level" must be a valid perlcritic level.'
);

Test::NoWarnings::had_no_warnings();
