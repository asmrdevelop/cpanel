package Whostmgr::Transfers::Systems::NobodyFiles;

# cpanel - Whostmgr/Transfers/Systems/NobodyFiles.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

# RR Audit: JNK

use Cpanel::NobodyFiles ();
use Cpanel::Exception   ();
use Try::Tiny;

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_prereq { return ['FileProtect']; }

sub get_phase { return 100; }

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores ownership of files previously owned by the “nobody” user in the home directory.') ];
}

sub get_restricted_available {
    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    my $nobodyfiles_path = "$extractdir/nobodyfiles";

    return 1 if !-s $nobodyfiles_path;

    my $user_homedir = $self->homedir();
    my $user         = $self->newuser();

    open( my $nobody_fh, "<", $nobodyfiles_path ) or do {
        return ( 0, $self->_locale()->maketext( 'The system failed to open the file “[_1]” because of an error: [_2]', $nobodyfiles_path, $! ) );
    };

    my $err;
    try {
        local $SIG{'__WARN__'} = sub {
            $self->warn(@_);
        };
        Cpanel::NobodyFiles::chown_nobodyfiles( $user_homedir, $nobody_fh, $user );
    }
    catch {
        $err = $_;
    };
    close $nobody_fh or do {
        $self->warn( $self->_locale()->maketext( 'The system failed to close the file “[_1]” because of an error: [_2]', $nobodyfiles_path, $! ) );
    };

    if ($err) {
        return ( 0, Cpanel::Exception::get_string($err) );
    }

    return 1;
}

*restricted_restore = \&unrestricted_restore;

1;
