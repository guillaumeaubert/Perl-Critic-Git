package Perl::Critic::Git;

use warnings;
use strict;

use Carp;
use Data::Dumper;
use File::Basename qw();
use Git::Repository qw( Blame );
use Perl::Critic qw();


=head1 NAME

Perl::Critic::Git - Bond git and Perl::Critic to blame the right people for violations.


=head1 VERSION

Version 1.1.2

=cut

our $VERSION = '1.1.2';


=head1 SYNOPSIS

	use Perl::Critic::Git;
	my $git_critic = Perl::Critic::Git->new(
		file   => $file,
		level  => $critique_level,         # or undef to use default profile
	);
	
	my $violations = $git_critic->report_violations(
		author => $author,                 # or undef for all
		since  => $date,                   # to critique only recent changes
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
PerlCritic profile for the system will be used.

#TODO: List allowed values from PerlCritic.

=back

=cut

sub new
{
	my ( $class, %args ) = @_;
	my $file = delete( $args{'file'} );
	my $level = delete( $args{'level'} );
	
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
		author => $author,                 # or undef for all
		since  => $date,                   # to critique only recent changes
	);

Parameters:

=over 4

=item * 'author'

Mandatory, the name of the author to search violations for.

=item * 'since'

Optional, a date (format YYYY-MM-DD) for which violations of the PBPs that are
older will be ignored. This allows critiquing only recent changes, instead of
forcing your author to fix an entire legacy file at once if only one line needs
to be modified.

=back

=cut

sub report_violations
{
	my ( $self, %args ) = @_;
	my $author = delete( $args{'author'} );
	my $since = delete( $args{'since'} );
	
	# Verify parameters.
	croak 'The argument "author" must be passed'
		if !defined( $author );
	
	# Analyze the file.
	$self->_analyze_file();
	
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

=cut

sub _analyze_file
{
	my ( $self ) = @_;
	
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
	
	# Do a git blame on the file.
	my ( undef, $directory, undef ) = File::Basename::fileparse( $file );
	my $repository = Git::Repository->new( work_tree => $directory );
	$self->{'git_blame_lines'} = $repository->blame( $file );
	
	# Run PerlCritic on the file.
	my $critic = Perl::Critic->new(
		'-severity' => defined( $self->_get_critique_level() )
			? $self->_get_critique_level()
			: undef,
	);
	$self->{'perlcritic_violations'} = [ $critic->critique( $file ) ];
	
	# Flag the file as analyzed.
	$self->_is_analyzed( 1 );
	
	return;
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


=head1 AUTHOR

Guillaume Aubert, C<< <aubertg at cpan.org> >>.


=head1 BUGS

Please report any bugs or feature requests to C<bug-perl-critic-git at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Perl-Critic-Git>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc Perl::Critic::Git


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Perl-Critic-Git>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Perl-Critic-Git>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Perl-Critic-Git>

=item * Search CPAN

L<http://search.cpan.org/dist/Perl-Critic-Git/>

=back


=head1 ACKNOWLEDGEMENTS

Thanks to ThinkGeek (L<http://www.thinkgeek.com/>) and its corporate overlords
at Geeknet (L<http://www.geek.net/>), for footing the bill while I eat pizza
and write code for them!


=head1 COPYRIGHT & LICENSE

Copyright 2012 Guillaume Aubert.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License version 3 as published by the Free
Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program. If not, see http://www.gnu.org/licenses/

=cut

1;
