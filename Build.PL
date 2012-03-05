use 5.006;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
	module_name         => 'Perl::Critic::Git',
	license             => 'artistic',
	dist_author         => q{Guillaume Aubert <aubertg@cpan.org>},
	dist_version_from   => 'lib/Perl/Critic/Git.pm',
	build_requires      =>
	{
		'Carp'                           => 0,
		'Data::Dumper'                   => 0,
		'English'                        => 0,
		'File::Basename'                 => 0,
		'File::Path'                     => 0,
		'File::Spec'                     => 0,
		'Git::Repository'                => 0,
		'Git::Repository::Plugin::Blame' => 0,
		'Perl::Critic'                   => 0,
		'Test::Deep'                     => 0,
		'Test::Exception'                => 0,
		'Test::Git'                      => 0,
		'Test::More'                     => 0,
	},
	requires            =>
	{
		'perl' => 5.006,
	},
	add_to_cleanup      =>
	[
		'Perl-Critic-Git-*',
	],
	create_makefile_pl  => 'traditional',
	configure_requires  =>
	{
		'Module::Build'                  => 0,
	},
	meta_merge          =>
	{
		resources                        =>
		{
			repository  => 'https://sourceforge.net/p/perlcriticgit/code',
			homepage    => 'https://metacpan.org/release/Perl-Critic-Git',
			bugtracker  => 'http://rt.cpan.org/NoAuth/ReportBug.html?Queue=perl-critic-git',
		},
	},
);

$builder->create_build_script();
