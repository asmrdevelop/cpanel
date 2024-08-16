package Cpanel::ImagePrep::Task::cpwhm_misc;

# cpanel - Cpanel/ImagePrep/Task/cpwhm_misc.pm     Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';
use Cpanel::Imports;
use Cpanel::DatastoreDir                    ();
use Cpanel::DatastoreDir::Init              ();
use Cpanel::SafeDir::RM                     ();
use Whostmgr::Setup::Completed              ();
use Whostmgr::Setup::EULA                   ();
use Whostmgr::Templates::Chrome::Directory  ();
use Whostmgr::Templates::Chrome::Resellers  ();
use Whostmgr::Templates::Command::Directory ();

=head1 NAME

Cpanel::ImagePrep::Task::cpwhm_misc - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<EOF;
Miscellaneous cleanup related to cPanel & WHM:

- In case a WHM login has already occurred (which is not advisable),
  indicate that WHM initial setup is not done yet, so it should still be
  performed on first login of new VMs launched from the image.

- Clear pwcache directories if present.

- Check for any unexpected occurrences of the root password hash under
  /var/cpanel. If found, abort, because we can't be sure whether it's
  safe to delete these files or not.

- Clear /var/cpanel/caches/_generated*_files files
EOF
}

sub _type { return 'non-repair only' }

sub _pre {
    my ($self) = @_;

    $self->_reset_initial_login_actions();
    $self->_clear_pwcache();

    $self->common->_unlink('/var/cpanel/cpanel.uuid');    # cp-analytics package
    Cpanel::SafeDir::RM::safermdir( Cpanel::DatastoreDir::PATH() );

    Whostmgr::Templates::Command::Directory::clear_cache_dir();
    Whostmgr::Templates::Chrome::Directory::clear_cache_directories();

    return $self->PRE_POST_OK;
}

sub _reset_initial_login_actions {
    my ($self) = @_;

    Whostmgr::Setup::EULA::set_not_accepted();
    $self->loginfo('Reset EULA acceptance, if any');

    Whostmgr::Setup::Completed::set_not_complete();
    $self->loginfo('Marked WHM initial setup not complete');

    return;
}

sub _clear_pwcache {
    my ($self) = @_;

    for my $dir (
        qw(
        /var/cpanel/@pwcache
        /var/cpanel/pw.cache
        /var/cpanel/user_pw_cache
        )
    ) {

        $self->loginfo("Deleting directory $dir");
        Cpanel::SafeDir::RM::safermdir($dir);
    }
    $self->loginfo('Cleaned up PwCache.');

    return;
}

sub _post {
    my ($self) = @_;

    $self->loginfo('Re-creating datastore directory');
    Cpanel::DatastoreDir::Init::initialize();
    Whostmgr::Templates::Chrome::Resellers::process_all_resellers();

    return $self->PRE_POST_OK;
}

1;
