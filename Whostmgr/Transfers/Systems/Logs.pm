package Whostmgr::Transfers::Systems::Logs;

# cpanel - Whostmgr/Transfers/Systems/Logs.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles::Apache              ();
use Cpanel::FileUtils::Dir                   ();
use Cpanel::Exception                        ();
use Cpanel::Pkgacct::Components::Logs::Utils ();
use Cpanel::SimpleSync::CORE                 ();

use Try::Tiny;

use parent qw(
  Whostmgr::Transfers::Systems
);

use constant get_restricted_available => 1;

my $ARCHIVE_LOGS_DIR = 'logs';

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores service access logs.') ];
}

sub restricted_restore {
    my ($self) = @_;

    my $username = $self->newuser();

    my $allowed_hr = Cpanel::Pkgacct::Components::Logs::Utils::get_user_log_files_lookup($username);

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    my $logs_dir = "$extractdir/$ARCHIVE_LOGS_DIR";

    my ( $err, $dir_nodes_ar );
    try {
        $dir_nodes_ar = eval { Cpanel::FileUtils::Dir::get_directory_nodes($logs_dir) };
    }
    catch {
        $err = $_;
    };

    return ( 0, Cpanel::Exception::get_string($err) ) if $err;

    for my $node (@$dir_nodes_ar) {
        if ( !exists $allowed_hr->{$node} ) {
            $self->{'_utils'}->add_dangerous_item("Rejecting invalid log file: $ARCHIVE_LOGS_DIR/$node");
            next;
        }

        my ( $sync_ok, $sync_msg ) = Cpanel::SimpleSync::CORE::syncfile( "$logs_dir/$node", Cpanel::ConfigFiles::Apache->new()->dir_domlogs(), $Cpanel::SimpleSync::CORE::NO_SYMLINKS, $Cpanel::SimpleSync::CORE::NO_CHOWN );
        if ( !$sync_ok ) {
            $self->warn( $self->_locale()->maketext( 'The system failed restore the log file: “[_1]” because of an error: [_2].', $node, $sync_msg ) );
        }
    }

    return 1;
}

*unrestricted_restore = \&restricted_restore;

1;
