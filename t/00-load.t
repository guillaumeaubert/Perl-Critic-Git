#!perl -T

use strict;
use warnings;

use Test::More tests => 2;
use Test::NoWarnings;


BEGIN
{
	use_ok( 'Perl::Critic::Git' );
}

diag( "Testing Perl::Critic::Git $Perl::Critic::Git::VERSION, Perl $], $^X" );
