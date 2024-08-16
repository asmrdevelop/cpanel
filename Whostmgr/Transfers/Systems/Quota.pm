package Whostmgr::Transfers::Systems::Quota;

# cpanel - Whostmgr/Transfers/Systems/Quota.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Cpanel::LoadFile   ();
use Cpanel::LoadModule ();
use Cpanel::Locale     ();
use Cpanel::Quota      ();
use Cpanel::Exception  ();

use Try::Tiny;

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_phase {
    return 100;
}

sub get_prereq {
    return ['PostRestoreActions'];
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores the account’s data storage quota.') ];
}

sub get_restricted_available {
    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    my $archive_quota_file = "$extractdir/quota";

    return 1 if !-s $archive_quota_file;

    my $newuser = $self->{'_utils'}->local_username();

    $self->start_action('Restoring quota');

    my $quota_from_archive = Cpanel::LoadFile::loadfile($archive_quota_file);

    if ( !defined $quota_from_archive ) {
        return ( 0, $self->_locale()->maketext( 'The system failed to load the file “[_1]” because of an error: [_2]', $archive_quota_file, $! ) );
    }

    if ($quota_from_archive) {
        my ($quota) = $quota_from_archive =~ m{([0-9]+)};

        $quota ||= 0;    # The default is unlimited

        Cpanel::LoadModule::load_perl_module('Cpanel::Quota::Blocks');
        Cpanel::LoadModule::load_perl_module('Cpanel::Quota::Common');
        my $blocks = $quota * $Cpanel::Quota::Common::MEGABYTES_TO_BLOCKS;
        try {
            'Cpanel::Quota::Blocks'->new()->set_user($newuser)->set_limits_if_quotas_enabled( { soft => $blocks, hard => $blocks } );
        }
        catch {
            $self->out( Cpanel::Exception::get_string($_) );
        };

        Cpanel::Quota::reset_cache($newuser);
    }

    return 1;
}

*restricted_restore = \&unrestricted_restore;

1;
