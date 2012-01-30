#!perl -T

use Test::More tests => 1;

BEGIN
{
	use_ok( 'Perl::Critic::Git' );
}

diag( "Testing Perl::Critic::Git $Perl::Critic::Git::VERSION, Perl $], $^X" );
