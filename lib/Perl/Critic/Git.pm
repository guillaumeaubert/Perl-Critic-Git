package Perl::Critic::Git;

use warnings;
use strict;

use Carp;
use Data::Dumper;
use File::Basename qw();
use Git::Repository qw( Blame Diff );
use Perl::Critic qw();
use List::BinarySearch qw();

=head1 NAME

Perl::Critic::Git - Bond git and Perl::Critic to blame the right people for violations.


=head1 VERSION

Version 1.3.1

=cut

our $VERSION = '1.3.1';


=head1 SYNOPSIS

	use Perl::Critic::Git;
	my $git_critic = Perl::Critic::Git->new(
		file   => $file,
		level  => $critique_level,         # or undef to use default profile
	);

	my $violations = $git_critic->report_violations(
		author => $author,
		since  => $date,                   # to critique only recent changes
	);

	my $diff_violations = $git_critic->diff_violations(
		from => $from_commit,
		to   => $to_commit,
	);


=head1 METHODS

=head2 new()

Create a new Perl::Critic::Git object.

	my $git_critic = Perl::Critic::Git->new(
		file   => $file,
		level  => $critique_level,         # or undef to use default profile
	);

Parameters:

=over 4

=item * 'file'

Mandatory, the path to a file in a Git repository.

=item * 'level'

Optional, to set a PerlCritic level. If it is not specified, the default
PerlCritic profile for the system will be used. Either name or number can
assigned from the table below:

    +---------------+-----------------+
    | Severity Name | Severity Number |
    +---------------+-----------------+
    | gentle        | 5               |
    | stern         | 4               |
    | harsh         | 3               |
    | cruel         | 2               |
    | brutal        | 1               |
    +---------------+-----------------+

=back

=cut

sub new
{
	my ( $class, %args ) = @_;

	my $file = delete( $args{'file'} );
	my $level = delete( $args{'level'} );

        if (scalar(keys %args)) {
            my $invalid_arg = join(",", keys %args);
            croak "Invalid argument '$invalid_arg' received to create a Perl::Critic::Git object";
        }

	# Check parameters.
	croak "Argument 'file' is needed to create a Perl::Critic::Git object"
		if !defined( $file ) || ( $file eq '' );
	croak "Argument 'file' is not a valid file path"
		unless -e $file;
	croak "Argument 'level' is not a valid PerlCritic level"
		if defined( $level ) && ( $level !~ /(?:gentle|5|stern|4|harsh|3|cruel|2|brutal|1)/x );

	# Create the object.
	my $self = bless(
		{
			'file'               => $file,
			'level'              => $level,
			'analysis_completed' => 0,
			'git_output'         => undef,
			'perlcritic_output'  => undef,
			'authors'            => undef,
		},
		$class
	);

	return $self;
}


=head2 get_authors()

Return an arrayref of all the authors found in git blame for the file analyzed.

	my $authors = $git_critic->get_authors();

=cut

sub get_authors
{
	my ( $self ) = @_;

	unless ( defined( $self->{'authors'} ) )
	{
		my $blame_lines = $self->get_blame_lines();

		# Find all the authors listed.
		my $authors = {};
		foreach my $blame_line ( @$blame_lines )
		{
			my $commit_attributes = $blame_line->get_commit_attributes();
			$authors->{ $commit_attributes->{'author-mail'} } = 1;
		}
		$self->{'authors'} = [ keys %$authors ];
	}

	return $self->{'authors'};
}


=head2 report_violations()

Report the violations for a given Git author.

	my $violations = $git_critic->report_violations(
		author => $author,
		since  => $date,                   # to critique only recent changes
	);

Parameters:

=over 4

=item * author (mandatory)

The name of the author to search violations for.

=item * since (optional)

A date (format YYYY-MM-DD) for which violations of the PBPs that are older will
be ignored. This allows critiquing only recent changes, instead of forcing your
author to fix an entire legacy file at once if only one line needs to be
modified.

=item * use_cache (default: 0)

Use a cached version of C<git diff> when available. See
L<Git::Repository::Plugin::Blame::Cache> for more information.

=back

=cut

sub report_violations
{
	my ( $self, %args ) = @_;
	my $author = delete( $args{'author'} );
	my $since = delete( $args{'since'} );
	my $use_cache = delete( $args{'use_cache'} ) || 0;

        if (scalar(keys %args)) {
            my $invalid_arg = join(",", keys %args);
            croak "Invalid argument '$invalid_arg' passed to report_violations()";
        }

	# Verify parameters.
	croak 'The argument "author" must be passed'
		if !defined( $author );

	# Analyze the file.
	$self->_analyze_file(
		use_cache => $use_cache,
	);

	# Run through all the violations and find the ones from the author we're
	# interested in.
	my $author_violations = [];
	my $perlcritic_violations = $self->get_perlcritic_violations();
	foreach my $violation ( @$perlcritic_violations )
	{
		my $line_number = $violation->line_number();
		my $blame_line = $self->get_blame_line( $line_number );
		my $commit_attributes = $blame_line->get_commit_attributes();

		# If the author doesn't match, skip.
		next unless $commit_attributes->{'author-mail'} eq $author;

		# If the parameters require filtering by time, do this here before we
		# add it to the list of violations.
		next if defined( $since ) && $commit_attributes->{'author-time'} < $since;

		# It passes all the search criteria, add it to the list.
		push( @$author_violations, $violation );
	}

	return $author_violations;
}


=head2 force_reanalyzing()

Force reanalyzing the file specified by the current object. This is useful
if the file has been modified since the Perl::Critic::Git object has been
created.

	$git_critic->force_reanalyzing();

=cut

sub force_reanalyzing
{
	my ( $self ) = @_;

	$self->_is_analyzed( 0 );

	return 1;
}


=head1 ACCESSORS

=head2 get_perlcritic_violations()

Return an arrayref of all the Perl::Critic::Violation objects found by running
Perl::Critic on the file specified by the current object.

	my $perlcritic_violations = $git_critic->get_perlcritic_violations();

=cut

sub get_perlcritic_violations
{
	my ( $self ) = @_;

	# Analyze the file.
	$self->_analyze_file();

	return $self->{'perlcritic_violations'}
}


=head2 get_blame_lines()

Return an arrayref of Git::Repository::Plugin::Blame::Line objects corresponding
to the lines in the file analyzed.

	my $blame_lines = $self->get_blame_lines();

=cut

sub get_blame_lines
{
	my ( $self ) = @_;

	# Analyze the file.
	$self->_analyze_file();

	return $self->{'git_blame_lines'};
}


=head2 get_blame_line()

Return a Git::Repository::Plugin::Blame::Line object corresponding to the line
number passed as parameter.

	my $blame_line = $git_critic->get_blame_line( 5 );

=cut

sub get_blame_line
{
	my ( $self, $line_number ) = @_;

	# Verify parameters.
	croak 'The first parameter must be an integer representing a line number in the file analyzed'
		if !defined( $line_number ) || $line_number !~ m/^\d+$/x || $line_number == 0;

	my $blame_lines = $self->get_blame_lines();
	croak 'The line number requested does not exist'
		if $line_number > scalar( @$blame_lines );

	return $blame_lines->[ $line_number - 1 ];
}


=head1 INTERNAL METHODS


=head2 _analyze_file()

Run "git blame" and "PerlCritic" on the file specified by the current object
and caches the results to speed reports later.

	$git_critic->_analyze_file();

Arguments:

=over 4

=item * use_cache (default: 0)

Use a cached version of C<git diff> when available.

=back

=cut

sub _analyze_file
{
	my ( $self, %args ) = @_;
	my $use_cache = delete( $args{'use_cache'} ) || 0;

	# If the file has already been analyzed, no need to do it again.
	return
		if $self->_is_analyzed();

	my $file = $self->_get_file();

	# Git::Repository uses GIT_DIR and GIT_WORK_TREE to determine the path
	# to the git repository when those environment variables are present.
	# This however poses problems here, when those variables point to a
	# different repository then the one the file to analyze belongs to,
	# or when they use relative paths.
	# To force Git::Repository to derive the git repository's path from
	# the file path, we thus locally delete GIT_DIR and GIT_WORK_TREE.
	local %ENV = %ENV;
	delete( $ENV{'GIT_DIR'} );
	delete( $ENV{'GIT_WORK_TREE'} );

	my $repository = $self->_git_repo;

	# Do a git blame on the file.
	$self->{'git_blame_lines'} = $repository->blame(
		$file,
		use_cache => $use_cache,
	);

	# Run PerlCritic on the file.
	$self->{'perlcritic_violations'} = [ $self->_critic->critique( $file ) ];

	# Flag the file as analyzed.
	$self->_is_analyzed( 1 );

	return;
}


=head2 _critic()

Lazy accessor for Perl::Critic object

	my $repo = $self->_critic();

=cut

sub _critic {
	my ($self) = @_;
	if ($self->{_critic}) {
		return $self->{_critic};
	}

	my $critic = Perl::Critic->new(
		'-severity' => defined( $self->_get_critique_level() )
			? $self->_get_critique_level()
			: undef,
	);
	$self->{_critic} = $critic;
	return $critic
}

=head2 _git_repo()

Lazy accessor for Git::Repository object

	my $repo = $self->_git_repo();

=cut


sub _git_repo {
	my ($self) = @_;
	if ($self->{_git_repo}) {
		return $self->{_git_repo};
	}

	my ( undef, $directory, undef ) = File::Basename::fileparse( $self->_get_file() );
	my $repository = Git::Repository->new( work_tree => $directory );
	$self->{_git_repo} = $repository;

	return $repository;
}

=head2 _is_analyzed()

Return whether the file specified by the current object has already been
analyzed with "git blame" and "PerlCritic".

	my $is_analyzed = $git_critic->_is_analyzed();

=cut

sub _is_analyzed
{
	my ( $self, $value ) = @_;

	$self->{'analysis_completed'} = $value
		if defined( $value );

	return $self->{'analysis_completed'};
}


=head2 _get_file()

Return the path to the file to analyze for the current object.

	my $file = $git_critic->_get_file();

=cut

sub _get_file
{
	my ( $self ) = @_;

	return $self->{'file'};
}


=head2 _get_critique_level()

Return the critique level selected when creating the current object.

	my $critique_level = $git_critic->_get_critique_level();

=cut

sub _get_critique_level
{
	my ( $self ) = @_;

	return $self->{'level'};
}


=head2 diff_violations()

Report the violations for diff between commits.

	my $violations = $git_critic->diff_violations(
		from => $from_commit,
		to   => $to_commit,
	);

Parameters:

=over 4

=item * from (mandatory)

Commit or branch from which we will analyze changes

=item * to (mandatory)

Commit or branch to which we will analyze changes

=cut

sub diff_violations
{
	my ( $self, %args ) = @_;
	my $from = delete( $args{'from'} );
	my $to = delete(  $args{'to'} );

	if (scalar(keys %args)) {
		my $invalid_arg = join(",", keys %args);
		croak "Invalid argument '$invalid_arg' passed to report_violations()";
	}

	# Verify parameters.
	croak 'The argument "from" must be passed'
		if !defined( $from );
	croak 'The argument "to" must be passed'
		if !defined( $to );

	my @diff_hunks = $self->_git_repo->diff($self->{'file'}, $from, $to);
	my @to_lines_numbers = map { $_->[0] } map { $_->to_lines } @diff_hunks;

	return () unless @diff_hunks;

	my @diff_violations;
	my $perlcritic_violations = $self->get_perlcritic_violations();
	foreach my $violation ( @$perlcritic_violations )
	{
		my $line_number = $violation->line_number();
		my $is_changed_line = List::BinarySearch::binsearch {$a <=> $b} $line_number, @to_lines_numbers;
		if ($is_changed_line) {
			push @diff_violations, $violation;
		}
	}

	return @diff_violations;
}


=head1 SEE ALSO

=over 4

=item * L<Perl::Critic>

=back


=head1 BUGS

Please report any bugs or feature requests through the web interface at
L<https://github.com/guillaumeaubert/Perl-Critic-Git/issues>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc Perl::Critic::Git


You can also look for information at:

=over 4

=item * GitHub (report bugs there)

L<https://github.com/guillaumeaubert/Perl-Critic-Git/issues>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Perl-Critic-Git>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Perl-Critic-Git>

=item * MetaCPAN

L<https://metacpan.org/release/Perl-Critic-Git>

=back


=head1 AUTHOR

L<Guillaume Aubert|https://metacpan.org/author/AUBERTG>,
C<< <aubertg at cpan.org> >>.


=head1 ACKNOWLEDGEMENTS

I originally developed this project for ThinkGeek
(L<http://www.thinkgeek.com/>). Thanks for allowing me to open-source it!


=head1 COPYRIGHT & LICENSE

Copyright 2012-2018 Guillaume Aubert.

This code is free software; you can redistribute it and/or modify it under the
same terms as Perl 5 itself.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the LICENSE file for more details.

=cut

1;
