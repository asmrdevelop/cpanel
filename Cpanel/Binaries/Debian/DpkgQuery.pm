package Cpanel::Binaries::Debian::DpkgQuery;

# cpanel - Cpanel/Binaries/Debian/DpkgQuery.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Binaries::Debian::DpkgQuery

=head1 DESCRIPTION

Interface to common dpkg-query commands.


=head1 WARNING

    ***************************************************************
    * DO NOT USE this in any new code! Prefer Cpanel::Pkgr instead
    ***************************************************************

=head1 SYNOPSIS

    my $dpkg_query = Cpanel::Binaries::Deiban::DpkgQuery->new;
    $dpkg_query->query('package1', ...)
    ...

=cut

use cPstrict;

use parent 'Cpanel::Binaries::Role::Debian';

=head1 METHODS

=head2 bin_path($self)

Provides the binary our parent SafeRunner should use.

=cut

sub bin_path ($self) {

    return '/usr/bin/dpkg-query';
}

=head2 query(@args)

A thin wrapper around dpkg-query

Returns a hashref of packages as the keys
and their versions as the values.

Returns an empty hashref on failure for
backwards compat.

Additional checks are done regarding whether
or not the package is installed or not, as
installing a package once will cause dpkg-query
to "know" about the package even after uninstallation.

=cut

sub query {
    my ( $self, @filter ) = @_;
    $self                    or _croak('query() method called without arguments.');
    ref $self eq __PACKAGE__ or _croak("query() must be called as a method.");

    my $answer = $self->cmd( "-W", "-f=" . $self->_get_format_string(), @filter );
    return _format_query_response($answer);
}

sub _get_format_string {
    my ($self) = @_;

    my $arch_str = $self->{'with_arch_suffix'} ? '.${Architecture}' : '';
    return '${binary:Package} ${Version}' . $arch_str . ' ${db:Status-Abbrev}\n';
}

sub _format_query_response {
    my ($answer) = @_;
    my $out = $answer->{output};
    return {
        map { ( split( m{\s+}, $_ ) )[ 0, 1 ] }
          grep {

            # Must have space between package name and version
            # Can't simply think it doesn't exist
            my $str = $_;

            # The value here can have trailing whitespace, breaking the substr -2 check below, so fix it before we get there
            $str =~ s/\s+$//g;
                 index( $str, 'is not installed' ) == -1
              && index( $str, " " )
              && index( $str, "no packages found" ) == -1
              && substr( $str, -2 ) eq 'ii';    # Filter out all but installed
          } split( "\n", $out )
    };
}

1;
