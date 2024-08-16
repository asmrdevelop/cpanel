package Cpanel::RepoQuery::Yum;

# cpanel - Cpanel/RepoQuery/Yum.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Binaries::RepoQuery ();

=head1 NAME

Cpanel::RepoQuery::Yum

=head1 SYNOPSIS

See Cpanel::RepoQuery for usage

=head1 DESCRIPTION

Module outlining "what to do" on YUM based systems when that's needed within
Cpanel::RepoQuery.

=head1 METHODS

=head2 new

The constructor. Should only be needed by callers who write tests for this.

=cut

sub new ( $class, $opts = undef ) {
    $opts //= {};

    my $self = {%$opts};
    bless $self, $class;

    return $self;
}

=head2 binary_repoquery

Returns Cpanel::Binaries::RepoQuery object or a cached version of this
if it exists.

=cut

sub binary_repoquery ($self) {

    return $self->{_repoquery} //= Cpanel::Binaries::RepoQuery->new();
}

=head2 what_provides($file)

Gets all packages providing $file (from installed repos).
Returns ARRAYREF of package description HASHREFs.

This previously was Cpanel::SysPkgs::Repoquery::whatprovides.

=cut

sub what_provides ( $self, $pkg_or_file ) {
    return $self->binary_repoquery->whatprovides($pkg_or_file);
}

=head2 get_all_packages_from_repo($repo_url)

Gets all packages from the URL given (should be a debian repo URL).
Returns ARRAY of package description HASHREFs.

=cut

sub get_all_packages_from_repo ( $self, $repo_url, $mirror_url = undef ) {

    my @attrs = qw{
      name
      summary
      description
      version
      release
      url
    };

    return $self->binary_repoquery->get_all_packages( $repo_url, @attrs );
}

1;
