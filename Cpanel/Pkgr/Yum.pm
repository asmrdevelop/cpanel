
# cpanel - Cpanel/Pkgr/Yum.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Pkgr::Yum;

=head1 NAME

Cpanel::Pkgr::Yum

=head1 DESCRIPTION

Wrapper around `rpm`. In the past most methods corresponded to switch names (qa, qf, etc).

WARNING: Prefer using Cpanel::Pkgr instead of calling Cpanel::Pkgr::Yum directly

=head1 SYNOPSIS

    # prefer the second call
    my $rpmservice = Cpanel::Pkgr::Yum->new( { 'with_arch_suffix' => 1 } ) ;
    $rpmservice->get_version('rpm1','rpm2');
    $rpmservice->what_owns('rpm1','rpm2')
    ...

=cut

use cPstrict;

use Cpanel::Binaries::Rpm       ();
use Cpanel::Binaries::RepoQuery ();

use parent 'Cpanel::Pkgr::Base';

sub name ($self) { return 'yum' }

# a packaging system can rely on more than a binary to get database information
#   for now yum mainly on 'bin/rpm' command, we could have merged Cpanel::Binaries::RPM
#   with this package, but this would be easier to maintain and add functionalities
sub binary_rpm ($self) {

    return $self->{_rpm} //= Cpanel::Binaries::Rpm->new();
}

sub binary_repoquery ($self) {

    return $self->{_repoquery} //= Cpanel::Binaries::RepoQuery->new();
}

sub query ( $self, @filter ) {

    return $self->binary_rpm->query(@filter);
}

sub is_installed ( $self, $package ) {

    return $self->binary_rpm->has_rpm($package);
}

=head2 installed_packages(@args)

=cut

sub installed_packages ( $self, @filter ) {

    return $self->binary_rpm->installed_packages(@filter);
}

=head2 what_owns(@args)

=cut

sub what_owns ( $self, @filter ) {

    return $self->binary_rpm->what_owns(@filter);
}

=head2 what_owns_no_errors(@list_of_files)

Similar to what_owns but do not raise errors for files not owned by a package.

Returns a HashRef with the package name and version which owns
the list of files.

    my $package_version = Cpanel::Pkgr::what_owns_no_errors( '/file1', '/file2' );

=cut

sub what_owns_no_errors ( $self, @list_of_files ) {

    return $self->binary_rpm->what_owns_no_errors(@list_of_files);
}

=head2 get_packages_dependencies(@packages)

Request dependencies for a list of packages.

Returns a HASHREF, where the key is the package name
and the value is one HASHREF where key is the dependency name
and value the version required.

=cut

sub get_packages_dependencies ( $self, @filter ) {

    return $self->binary_rpm->qR(@filter);
}

sub list_files_from_package_path ( $self, $rpm_file_path ) {

    return $self->binary_rpm->list_files_from_package_path($rpm_file_path);
}

# Would have been ql under the old Cpanel::RPM nomenclature
sub list_files_from_installed_package ( $self, $rpm_name ) {

    return $self->binary_rpm->list_files_from_installed_package($rpm_name);
}

# --query --whatprovides
sub what_provides ( $self, $pkg_or_file ) {

    return $self->binary_rpm->what_provides($pkg_or_file);
}

=head2 is_capability_available( $search )

Check if a capability (package, virtual package, file...) is available.
Returns a boolean: 1/0.

=cut

sub is_capability_available ( $self, $search ) {
    return 0 unless defined $search;
    return $self->what_provides($search) ? 1 : 0;
}

# Previously this was Cpanel::SysPkgs::Repoquery::installed_whatprovides
# Unsurprisingly, this means it is similar to "what_provides".
# That said, it provides an ARRAYREF of package description HASHREFS,
# instead of just a list of packages, so therein lies the difference.
sub what_provides_with_details ( $self, $pkg_or_file ) {
    return $self->binary_rpm->what_provides_with_details($pkg_or_file);
}

# --query --requires
sub get_package_requires ( $self, $pkg ) {

    # Note: this is doing '-q --requires' and not '-q --what-requires'

    return $self->binary_rpm->what_requires($pkg);
}

=head2 add_repo_keys( key1, key2, ... )

=cut

sub add_repo_keys ( $self, @keys2import ) {

    return $self->binary_rpm->add_repo_keys(@keys2import);
}

=head2 get_version_for_packages( rpm1 rpm2 ... rpmN )

Convenience method to return the version of the RPM(s) provided (output of -q).

If no version is returned, the RPM is not installed.

Example output:

    {
        rpm1 => 'version1',
        rpm2 => 'version2'
    }

=cut

sub get_version_for_packages ( $self, @list ) {

    return $self->binary_rpm->get_version(@list);
}

sub get_version_with_arch_suffix ( $self, @list ) {

    local $self->binary_rpm->{'with_arch_suffix'} = 1;

    return $self->binary_rpm->get_version(@list);
}

=head2 install_or_upgrade_from_file( path2rpm1, path2rpm2, ... )

=cut

sub install_or_upgrade_from_file ( $self, @rpm_paths ) {

    return $self->binary_rpm->install_or_upgrade_from_file(@rpm_paths);
}

=head2 verify_package( $package )

Validates the files associated with an installed package.

=cut

sub verify_package ( $self, $package, $file = undef ) {

    return $self->binary_rpm->verify_package( $package, $file );
}

=head2 package_file_is_signed_by_cpanel( path2rpm )

=cut

sub package_file_is_signed_by_cpanel ( $self, $file ) {

    return $self->binary_rpm->package_file_is_signed_by_cpanel($file);
}

=head2 get_package_scripts( @pkgs )

=cut

sub get_package_scripts ( $self, @pkgs ) {
    return $self->binary_rpm->get_rpm_scripts(@pkgs);
}

=head2 verify_package_manager_can_install_packages( $logger = undef )

=cut

sub verify_package_manager_can_install_packages ( $self, $logger = undef ) {

    # wrapper for logging
    my $do_log;
    if ($logger) {
        $do_log = sub ($msg) {
            return unless defined $msg;
            chomp $msg;
            $logger->info("$msg\n");
        };
    }
    else {
        $do_log = sub ($msg) { return };
    }

    my $answer = $self->binary_rpm->cmd_with_logger( $logger, qw{ -q --nosignature --nodigest glibc } );
    if ( my $status = $answer->{status} ) {
        my $exit_code = $status >> 8;
        my $output    = $answer->{output} // '';
        my $statusmsg = "FAIL: RPM DB error: $output (exit code $exit_code)";
        $do_log->($statusmsg);
        return ( 0, $statusmsg );
    }

    return ( 1, '' ) if $ENV{'CPANEL_BASE_INSTALL'};

    # try to install / remove a simple package

    $do_log->("Testing if rpm_is_working RPM is installed");

    $answer = $self->binary_rpm->cmd(qw{ -q --nosignature --nodigest rpm_is_working });
    if ( $answer->{status} == 0 ) {    # success when the rpm is installed
        $do_log->("Removing RPM rpm_is_working");

        $answer = $self->binary_rpm->cmd_with_logger( $logger, qw{ -e --allmatches rpm_is_working } );    #

        # at the very least, log if we can't remove rpm_is_working; treat as ok
        if ( my $status = $answer->{status} ) {
            my $msg = $answer->{output} // q{Reason unknown.};
            $do_log->("Failed to remove rpm_is_working. $msg");
        }
    }

    my $local_pkg = '/usr/local/cpanel/src/rpm_is_working-1.0-0.noarch.rpm';

    if ( -e $local_pkg && !-z $local_pkg ) {

        # Test if we can install a simple RPM.
        $do_log->("Testing if it's possible to install a simple RPM");
        $answer = $self->binary_rpm->cmd_with_logger( $logger, '-Uvh', '--force', $local_pkg );

        if ( my $status = $answer->{status} ) {
            my $exit_code = $status >> 8;
            my $msg       = qq[Fail to install $local_pkg file (exit code $exit_code)];
            $do_log->($msg);
            return ( 0, $msg );
        }
        elsif ( !-e '/usr/local/cpanel/src/rpm_is_working' ) {
            my $msg = "The RPM did not appear to install.";
            $do_log->($msg);
            return ( 0, $msg );
        }
        else {
            $answer = $self->binary_rpm->cmd_with_logger( $logger, qw{ -e rpm_is_working } );

            # at the very least, log if we can't remove rpm_is_working; treat as ok
            if ( my $status = $answer->{status} ) {
                $do_log->("Failed to remove rpm_is_working.");
            }
        }
    }

    return ( 1, '' );
}

=head2 installed_cpanel_obsoletes ( )

=cut

sub installed_cpanel_obsoletes ($self) {
    return $self->binary_rpm->installed_obsoletes();
}

=head2 remove_packages_nodeps( @pkgs )

=cut

sub remove_packages_nodeps ( $self, @pkgs ) {
    return $self->binary_rpm->remove_packages_nodeps(@pkgs);
}

=head2 lock_for_external_install ( $logger )

retrieve a cPanel lock for using the rpm/yum system.

=cut

sub lock_for_external_install ( $self, $logger ) {
    return $self->binary_rpm->get_lock_for_cmd( $logger, ['and install external system packages.'] );    # rpm -U needs a lock. we'll use this to make sure the system gives a lock.
}

1;
