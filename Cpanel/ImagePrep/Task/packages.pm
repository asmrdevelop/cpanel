
# cpanel - Cpanel/ImagePrep/Task/packages.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task::packages;

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';
use Cpanel::Imports;
use Cpanel::JSON        ();
use Cpanel::Pkgr        ();
use Cpanel::SafeDir::RM ();
use Cpanel::SysPkgs     ();

use constant DELETE_PACKAGES => (
    'cpanel-ccs-calendarserver',
    'cpanel-z-push',
);
use constant DELETE_DIRS => (
    '/opt/cpanel-ccs',    # Package removal alone does not clean out the per-instance data
    '/usr/local/cpanel/3rdparty/usr/share/z-push',
);
use constant INSTALL_LIST => '/var/cpanel/Cpanel-ImagePrep-Task-packages.install.json';    # This name can be changed later

=head1 NAME

Cpanel::ImagePrep::Task::packages - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=head1 METHODS

=head2 request(@install_list)

(Unique to this module)

Given a list of packages requested by the user, save these in the install list so that they
will be automatically installed on first boot in addition to any packages that might need to
get reinstalled after removal.

The request persists beyond the life of the object because it is written to disk and will be
inherited by the next object.

=cut

sub request {
    my ( $self, @install_list ) = @_;
    die 'not static' unless ref $self;

    $self->loginfo( 'User requested package installation on first boot: ' . join( ', ', @install_list ) );
    Cpanel::JSON::DumpFile( INSTALL_LIST, \@install_list );

    return 1;
}

sub _description {
    return <<EOF;
Handles two types of package uninstallation and/or installation:

  - Those which were requested on the command-line arguments using --instance-packages=...

  - Optional packages which might already be installed due to configuration changes made on
    the server, but which should not be built into an image. Instead, they will be deleted
    during snapshot_prep (including any per-instance data) and reinstalled on first-boot of
    each instance via the post_snapshot service.
EOF
}

sub _type { return 'non-repair only' }

sub _pre {
    my ($self) = @_;

    my @install_list;
    if ( -f INSTALL_LIST ) {
        @install_list = @{ Cpanel::JSON::LoadFile(INSTALL_LIST) };
        $self->loginfo( 'Packages already marked for installation on first boot: ' . join( ', ', @install_list ) ) if @install_list;
    }

    my @to_remove;
    for my $p (DELETE_PACKAGES) {
        if ( Cpanel::Pkgr::is_installed($p) ) {
            push @to_remove, $p;
        }
    }
    push @install_list, @to_remove;

    my %dedup;
    @install_list = grep { !$dedup{$_}++ } @install_list;

    # This will be empty unless someone has either requested a package installation or
    # pre-installed a package that should not be pre-installed.
    if (@install_list) {
        $self->loginfo( 'Package install list for first boot: ' . join( ', ', @install_list ) );
        Cpanel::JSON::DumpFile( INSTALL_LIST, \@install_list );
    }

    if (@to_remove) {
        $self->loginfo( 'Removing packages to prepare for image: ' . join( ', ', @to_remove ) );
        Cpanel::Pkgr::remove_packages_nodeps(@to_remove);
    }

    for my $dir (DELETE_DIRS) {
        if ( -d $dir ) {
            $self->loginfo("Deleting remaining contents of directory '$dir'");
            Cpanel::SafeDir::RM::safermdir($dir)
              or return $self->PRE_POST_FAILED;
        }
    }

    return $self->PRE_POST_OK;
}

sub _post {
    my ($self) = @_;

    my @to_install;
    if ( -f INSTALL_LIST ) {
        @to_install = @{ Cpanel::JSON::LoadFile(INSTALL_LIST) };
    }

    if (@to_install) {
        $self->loginfo( 'Installing packages: ' . join( ', ', @to_install ) );

        my $syspkgs = Cpanel::SysPkgs->new();
        $syspkgs->install_packages(
            packages => \@to_install,
        );

        $self->common->_unlink(INSTALL_LIST);
    }
    else {
        $self->loginfo('No packages to install');
    }

    return $self->PRE_POST_OK;
}

=head1 INSTANCE METHODS

As a subclass of C<Cpanel::ImagePrep::Task>, this module has the same basic interface as any
other Task/*.pm module.

=cut

1;
