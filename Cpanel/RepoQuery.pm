package Cpanel::RepoQuery;

# cpanel - Cpanel/RepoQuery.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::OS             ();
use Cpanel::RepoQuery::Apt ();    # PPI USE OK - make these available at runtime regardless of installed OS.
use Cpanel::RepoQuery::Yum ();    # PPI USE OK - make these available at runtime regardless of installed OS.

=head1 NAME

Cpanel::RepoQuery

=head1 DESCRIPTION

Cpanel::RepoQuery provides an abstraction layer to request
common questions about packages that exist on a remote repository.

Under the hood it uses a singleton for you, so you do
not have to create an object or call the singleton yourself.

This interface IS NOT for querying the local package database or
making changes on the system (like installing packages).
For that, you should use either Cpanel::Pkgr or Cpanel::SysPkgs (respectively).

There was once a 'Cpanel::SysPkgs::RepoQuery' as well, though at one point
in development, it was thought that this functionality should be moved into
Pkgr. Unfortunately, at a later point in development, this decision was
realized to be not a great one. That said, the calling convention had already
changed along with subroutine names, thus making a Pkgr-like interface
instead of a SysPkgs one probably for the best. As such, we break with the old
namespace.

=head1 SYNOPSIS

    my $all_pkgs = Cpanel::RepoQuery::get_all_packages_from_repo();
    my $provides = Cpanel::RepoQuery::what_provides_from_repo('some_package');
    ...

=cut

=head1 METHODS

=head2 factory

Return a Cpanel::RepoQuery::* object, be it Apt or Yum

It returns either a Cpanel::RepoQuery::Apt or Cpanel::RepoQuery::Yum object

=cut

our $REPOQUERY;

sub factory {

    die "Cannot compile " . __PACKAGE__ if $INC{'B/C.pm'};

    my $pkg = "Cpanel::RepoQuery::" . Cpanel::OS::package_manager_module();
    return $pkg->new;
}

sub instance {
    $REPOQUERY //= factory();

    return $REPOQUERY;
}

=head2 what_provides( $search )

=head3 Description

Similar to Pkgr's what_provides_with_details, but explicitly queries the
remote repository instead of local details.

=head3 SEE ALSO

Cpanel::Pkgr

=head3 Arguments

C<search> - String - A feature or file provided by the desired package(s).

=head3 Returns

This function returns an array ref of hash refs, each of which contains the following fields:

=over

=item - name - String - The name of the package.

=item - version - String - The version number of the package.

=item - release - String - The release number of the package.

=item - arch - String - The architecture of the package. Usually one of i386, x86_64, or noarch.

=item - group - String - The category of the software.

=item - summary - String - The one-line description of the package.

=item - description - String - The multiline description of the package.

=back

    my $packages = Cpanel::RepoQuery::what_provides_with_repo( 'rockman' );
    # dump
     [
       {
         'arch' => 'x86_64',
         'description' => 'Robotics code from the future stolen by Dr. Wily',
         'group' => 'Artificial Intelligence/World Domination',
         'name' => 'rockman',
         'release' => '2.Roll',
         'summary' => 'Cyber ELF headers for proto-man successor machines',
         'version' => '20xx'
       },
       ...
     ]

=cut

sub what_provides ($search) {
    return instance()->what_provides($search);
}

=head2 get_all_packages_from_repo()

=head3 Description

Returns ARRAYREF of package description HASHREFs.

See POD for what_provides_with_repo regarding what the individual entries
should look like.

=cut

sub get_all_packages_from_repo ( $repo_url, $mirror_url = undef ) {
    return instance()->get_all_packages_from_repo( $repo_url, $mirror_url );
}

1;
