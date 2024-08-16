package Cpanel::Pkgr;

# cpanel - Cpanel/Pkgr.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::OS    ();
use Cpanel::Alarm ();

use Cpanel::Pkgr::Apt ();    # PPI USE OK - make these available at runtime regardless of installed OS.
use Cpanel::Pkgr::Yum ();    # PPI USE OK - make these available at runtime regardless of installed OS.

use constant TIMEOUT => 10 * 60;

=head1 NAME

Cpanel::Pkgr

=head1 DESCRIPTION

Cpanel::Pkgr provides an abstraction layer to request
common questions about locally installed packages.

Under the hood it uses a singleton for you, so you do
not have to create an object or call the singleton yourself.

This interface IS NOT for querying the upstream distro or asking it for things (like installing packages).
For that, you should use Cpanel::SysPkgs.

=head1 SYNOPSIS

    my $version      = Cpanel::Pkgr::get_package_version('some_package');
    my $is_installed = Cpanel::Pkgr::is_installed('some_package');
    ...

=cut

=head1 METHODS

=head2 factory

Return a Cpanel::Pkgr object, either a Cpanel::Pkgr::Apt or Cpanel::Pkgr::Yum

A factory to get a Cpanel::Pkgr object
It returns either a Cpanel::Pkgr::Apt or Cpanel::Pkgr::Yum object

=cut

our $PKGR;

sub factory {    # just a factory

    die "Cannot compile " . __PACKAGE__ if $INC{'B/C.pm'};

    my $pkg = "Cpanel::Pkgr::" . Cpanel::OS::package_manager_module();
    return $pkg->new;
}

sub instance {
    $PKGR //= factory();

    return $PKGR;
}

=head2 name( $pkg )

Returns the name of the packager type: 'apt' or 'yum'

=cut

sub name() {
    return instance()->name();
}

=head2 get_package_version( $pkg )

Returns the version of a single package.
Returns 'undef' when not installed.

Prefer using 'get_package_version' when possible

=cut

sub get_package_version ($pkg) {    # ... maybe rename at the end...
    return instance()->get_package_version($pkg);
}

=head2 is_installed( $pkg )

Returns a boolean value, true when the package is installed.

=cut

sub is_installed ($pkg) {
    return instance()->is_installed($pkg);
}

=head2 add_repo_keys( key1, key2, ... )

=cut

sub add_repo_keys (@keys2import) {
    return instance()->add_repo_keys(@keys2import);
}

=head2 get_version(@pkg)

Check the version for a list of packages.
Returns a HASHREF where the key is the package name and the value the version.

=cut

sub get_version_for_packages (@pkg) {
    return instance()->get_version_for_packages(@pkg);
}

=head2 get_version(@pkg)

This is similar to get_version, with the exception that
each version number has an extra suffix with the package
architecture used: .x86_64, .noarch on CentOS or .amd64, .all, ...
on debian systems.

=cut

sub get_version_with_arch_suffix (@pkg) {
    return instance()->get_version_with_arch_suffix(@pkg);
}

=head2 query(@filter)

Perform a custom query to the packaging system

=cut

sub query (@filter) {
    return instance()->query(@filter);
}

=head2 get_packages_dependencies(@packages)

Request dependencies for a list of packages.

Returns a HASHREF, where the key is the package name
and the value is one HASHREF where key is the dependency name
and value the version required.

=cut

sub get_packages_dependencies (@filter) {
    return instance()->get_packages_dependencies(@filter);
}

=head2 installed_packages(@filters)

Returns a hashref with the list of installed package.
Key: package name, Value: package version

You can use filter using glob, like 'cpanel-*'

    my $all_pkg_version = Cpanel::Pkgr::installed_packages();
    my $pkg_version     = Cpanel::Pkgr::installed_packages('cpanel-*');

=cut

sub installed_packages (@filter) {
    return instance()->installed_packages(@filter);
}

=head2 install_or_upgrade_from_file( $path2pkg1, $path2pkg2, ... )

Install or upgrade a list of packages using the local path.

=cut

# FIXME: This call has no standardized return values or exception behavior.

sub install_or_upgrade_from_file (@paths) {
    return instance()->install_or_upgrade_from_file(@paths);
}

=head2 list_files_from_package_path( $path2pkg )

List all files from a package on disk, using its local path.
Returns a list of files. (not a reference)

    my @files = Cpanel::Pkgr::list_files_from_package_path( '/path/to/package.[rpm|deb]' );

=cut

sub list_files_from_package_path ($path) {
    return instance()->list_files_from_package_path($path);
}

=head2 list_files_from_installed_package( $pkg_name )

List all files from an installed package.

    my @files = Cpanel::Pkgr::list_files_from_installed_package( 'tar' );

=cut

sub list_files_from_installed_package ($pkg_name) {
    return instance()->list_files_from_installed_package($pkg_name);
}

=head2 package_file_is_signed_by_cpanel( path2package )

=cut

sub package_file_is_signed_by_cpanel ($file) {
    return instance()->package_file_is_signed_by_cpanel($file);
}

=head2 verify_package ( $package, $file=undef )

Validates the files associated with an installed package.

If you pass a file as a second argument, only the one file in that package will be validated.

=cut

sub verify_package ( $package, $file = undef ) {
    return instance()->verify_package( $package, $file );
}

=head2 what_package_owns_this_file($file)

Returns the name of the package which owns a file

    my $pkg = Cpanel::Pkgr::what_package_owns_this_file( '/bin/tar' );
    $pkg eq 'tar' or die;

=cut

sub what_package_owns_this_file ($file) {
    return instance()->what_package_owns_this_file($file);
}

=head2 what_owns(@list_of_files)

Returns a HashRef with the package name and version which owns
the list of files.

    my $package_version = Cpanel::Pkgr::what_owns( '/file1', '/file2' );

=cut

sub what_owns (@list_of_files) {

    die('what_owns() requires at least one search filter')
      if !@list_of_files;

    return instance()->what_owns(@list_of_files);
}

=head2 what_owns_no_errors(@list_of_files)

Similar to what_owns but do not raise errors for files not owned by a package.

Returns a HashRef with the package name and version which owns
the list of files.

    my $package_version = Cpanel::Pkgr::what_owns_no_errors( '/file1', '/file2' );

=cut

sub what_owns_no_errors (@list_of_files) {

    die('what_owns() requires at least one search filter')
      if !@list_of_files;

    return instance()->what_owns_no_errors(@list_of_files);
}

=head2 what_provides( $search )

Used to search what package provides a file, package or virtual package.
Returns the package name.

    my $package_version = Cpanel::Pkgr::what_owns( '/file1', '/file2' );

    my $package_name = $pkgr->what_provides('cpanel-node');
    my $package_name = $pkgr->what_provides('cpanel-perl'); # virtual package
    my $package_name = $pkgr->what_provides('/bin/tar');

=cut

sub what_provides ($search) {
    return instance()->what_provides($search);
}

=head2 is_capability_available( $search )

Check if a capability (package, virtual package, file...) is available.
Returns a boolean: 1/0.

=cut

sub is_capability_available ($search) {
    return instance->is_capability_available($search);
}

=head2 what_provides_with_details( $search )

=head3 Description

Similar to what_provides but with some extra details about the package(s).

Where C<search> is the name of a feature or file provided by one or more RPMs, look up all packages
that provide that item.

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

    my $package_version = Cpanel::Pkgr::what_provides( 'cpanel-perl-536' );
    # dump
     [
       {
         'arch' => 'x86_64',
         'description' => 'This package is designed for use of cPanel perl scripts only.
     It is suggested you use the perl that came with your OS for use in cgi scripts, etc.',
         'group' => 'Development/Perl',
         'name' => 'cpanel-perl-536',
         'release' => '1.cp108',
         'summary' => 'The Perl programming language',
         'version' => '5.36.0'
       }
     ]

=cut

sub what_provides_with_details ($search) {
    return instance()->what_provides_with_details($search);
}

=head2 get_package_requires( $pkg )

Returns one HashRef with the requires for the package.

    my $requires = Cpanel::Pkgr::get_package_requires( 'cpanel-node' );

=cut

sub get_package_requires ($pkg) {
    return instance()->get_package_requires($pkg);
}

=head2 get_package_scripts( @pkgs )

Returns one HashRef with the scripts provided by each package.

    my $scripts = Cpanel::Pkgr::get_package_scripts( 'cpanel-dovecot', 'cpanel-exim' );

=cut

sub get_package_scripts (@pkgs) {
    return instance()->get_package_scripts(@pkgs);
}

=head2 verify_package_manager_can_install_packages( $logger = undef )

Check the sanity of the package system.
Returns a list, with the first variable being the status:
- status=0: the package system is not sane
- status=1: the package system seems sane

The additional value is a message explaining why the package
system is not sane.

    my ( $status, $message ) = Cpanel::Pkgr::verify_package_manager_can_install_packages();

=cut

sub verify_package_manager_can_install_packages ( $logger = undef ) {

    my $alarm_class = 'TimeoutAlarm';

    my $alarm = Cpanel::Alarm->new(
        TIMEOUT(),
        sub {    #
            die bless {}, $alarm_class;    #
        }
    );

    my ( $status, $msg );
    eval {
        ( $status, $msg ) = instance()->verify_package_manager_can_install_packages($logger);
        1;
    } or do {
        $msg //= $@ // q[Unknown PackageManager issue];
        if ( ref $@ eq $alarm_class ) {
            $msg = q[TIMEOUT: checking package manager sanity];
        }
        return ( 0, $msg );
    };

    return ( $status, $msg );
}

=head2 installed_cpanel_obsoletes ( )

Provides a list of installed packages which are obsoleted by something else.

Returns a hash ref with a list of package/versions as key/value.

=cut

sub installed_cpanel_obsoletes () {
    my $obsoletes = instance()->installed_cpanel_obsoletes();

    # Filter out only known packages provided by check_cpanel_rpms. As of 98, ALL cpanel-rpms should begin with cpanel-.
    my @cpanel_obsoletes = grep { m/^(cpanel-|dovecot|exim|p0f|proftpd|pure-ftpd|site-publisher).+\.cp11/ } @$obsoletes;
    return \@cpanel_obsoletes;
}

=head2 remove_packages_nodeps( @pkgs )

    Remove @pkgs without regard for dependencies.

=cut

sub remove_packages_nodeps (@packages) {
    return instance()->remove_packages_nodeps(@packages);
}

=head2 lock_for_external_install ( $logger )

Use this interface to block other cPanel systems from accessing the distro
packaging system while external systems might be interacting with it.

Returns a scalar which releases the lock when it goes out of scope.

=cut

sub lock_for_external_install ($logger) {
    return instance()->lock_for_external_install($logger);
}

1;
