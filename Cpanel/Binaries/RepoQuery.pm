package Cpanel::Binaries::RepoQuery;

# cpanel - Cpanel/Binaries/RepoQuery.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Binaries::RepoQuery

=head1 DESCRIPTION

Wrapper around `repoquery`.

=head1 WARNING

    ***************************************************************
    * DO NOT USE this in any new code! Prefer Cpanel::Pkgr instead
    ***************************************************************

=head1 SYNOPSIS

    my $repoquery = Cpanel::Binaries::RepoQuery->new();
    $repoquery->get_all_packages( BASEURL, ATTR1, ATTR2, ...);
    $repoquery->whatprovides( 'rpm1' )
    ...

=cut

use cPstrict;

use Cpanel::Context  ();
use Cpanel::OS       ();
use Cpanel::Binaries ();

use parent 'Cpanel::Binaries::Role::Cmd';

=head1 METHODS

=head2 bin_path

Provides the binary our parent SafeRunner should use.

=cut

sub bin_path {

    my $path = Cpanel::Binaries::path('repoquery');

    die("Unable to find the repoquery binary\n") unless -x $path;

    return $path;
}

sub lock_to_hold { return 'repoquery' }

=head2 lang

get_all_packages needs utf8 encoding on to get legible descriptions from upstream.

=cut

sub lang { return 'en_US.UTF-8' }

=head2 @pkgs = get_all_packages( BASEURL, ATTR1, ATTR2, ... )

Returns a list of hashes, one hash for each package that the remote repo
reports. The hashes contain the attributes as given in the function call.

***NOTE***

In order to have similar output to c7 and c6 on c8, the C<--latest-limit 1>
option will be passed into C<repoquery>.

To see a list of available attributes, run C<repoquery --querytags>.

=cut

sub get_all_packages ( $self, $baseurl, @attrs ) {

    Cpanel::Context::must_be_list();

    die "Need base URL!" if !$baseurl;

    if ( !@attrs ) {    # default attributes
        @attrs = (
            'name',
            'summary',
            'description',
            'version',
            'release',
            'url',
        );
    }

    my $attr_separator = _make_separator('attr');
    my $pkg_separator  = _make_separator('pkg');

    my $pkg_qf = join( $attr_separator, map { "%{$_}" } @attrs );

    my $id = '___REPOQUERY___';

    #NB: The test depends on key/value joined into a single arg.
    my @args = (
        "--repofrompath=$id,$baseurl",
        "--repoid=$id",
        '--all',
        "--qf=$pkg_qf$pkg_separator",
    );

    # Add new opt for DNF if needed
    push @args, '--latest-limit=1' if Cpanel::OS::package_manager() eq 'dnf';

    my $answer = $self->cmd(@args);

    return [] unless $answer->{'status'} == 0;

    my $out = $answer->{'output'} // '';

    $out =~ s<\A\s+|\s+\z><>g;

    my @pkgs = split m<\Q$pkg_separator\E>, $out;

    foreach my $pkg (@pkgs) {
        my %pkgg;
        @pkgg{@attrs} = split m<\Q$attr_separator\E>, $pkg;
        s<\A\s+|\s+\z><>g for values %pkgg;
        $pkg = \%pkgg;
    }

    return @pkgs;
}

=head2 whatprovides(ITEM)

=head3 Description

Where ITEM is the name of a feature or file provided by one or more RPMs, look up all packages
that provide that item.

=head3 Arguments

ITEM - String - A feature or file provided by the desired package(s).

=head3 Returns

This function returns an array ref of hash refs, each of which contains the following fields:

=over

=item - repoid - String - The short name of the repository providing the package.

=item - name - String - The name of the package.

=item - version - String - The version number of the package.

=item - release - String - The release number of the package.

=item - arch - String - The architecture of the package. Usually one of i386, x86_64, or noarch.

=item - group - String - The category of the software.

=item - summary - String - The one-line description of the package.

=item - description - String - The multiline description of the package.

=back

=cut

sub whatprovides ( $self, $item ) {

    _croak('You must specify a feature or file to search for.') unless defined $item;

    my @attrs = ( 'repoid', 'name', 'version', 'release', 'arch', 'group', 'summary', 'description' );

    my $attr_separator = _make_separator('attr');
    my $pkg_separator  = _make_separator('pkg');

    my $pkg_qf = join( $attr_separator, map { "%{$_}" } @attrs );

    my $query_format = join( $attr_separator, map { "\%{$_}" } @attrs ) . $pkg_separator;

    my $answer = $self->cmd( '--qf', $query_format, '--whatprovides', $item );

    #return [] if $answer->{'status'};

    my $output = $answer->{'output'} // '';

    my @records;
    for my $rpm_record ( split /\Q$pkg_separator\E/, $output ) {
        my %record;
        ( @record{@attrs} = map { my $e = $_; $e =~ s{^\n+}{}; chomp $e; $e; } split /\Q$attr_separator\E/, $rpm_record ) == scalar @attrs or next;
        push @records, \%record if scalar keys %record;
    }

    return \@records;
}

sub _make_separator ($type) {
    state $separator = '<>~:;' x 3;    # from RepoQuery

    return join( '-', $separator, time, $$, $type, $separator );
}

sub _croak {
    require Carp;
    goto \&Carp::croak;
}

1;
