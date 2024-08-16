package Whostmgr::Transfers::Systems::Shell;

# cpanel - Whostmgr/Transfers/Systems/Shell.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use AcctLock                  ();
use Cpanel::LoadFile          ();
use Cpanel::Locale            ();
use Cpanel::OrDie             ();
use Cpanel::Shell             ();
use Whostmgr::Accounts::Shell ();

use base qw(
  Whostmgr::Transfers::Systems
);

my %restricted_shells_allowed = (
    noshell   => $Cpanel::Shell::NO_SHELL,
    jailshell => $Cpanel::Shell::JAIL_SHELL,
);

my $DEFAULT_RESTRICTED_SHELL = 'jailshell';

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores the account’s shell.') ];
}

sub get_restricted_available {
    return 1;
}

sub get_restricted_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext( 'In restricted mode, the system will set any account that requests a shell other than [list_or_quoted,_1] to use “[_2]”.', [ keys %restricted_shells_allowed ], $DEFAULT_RESTRICTED_SHELL ) ];
}

sub unrestricted_restore {
    my ($self) = @_;

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    my $shell_file = "$extractdir/shell";

    return 1 if !-s $shell_file;    #Nothing to do!

    $self->start_action('Restoring shell');

    local $!;
    my $shell = Cpanel::LoadFile::loadfile("$extractdir/shell");
    if ($!) {
        return ( 0, $self->_locale()->maketext( 'The system failed to read the file “[_1]” because of an error: [_2]', $shell_file, $! ) );
    }

    #NOTE: Beyond here, we always have to call acctunlock().
    AcctLock::acctlock() or do {
        $self->warn( $self->_locale()->maketext('The system failed to lock system utilities for shell restoration.') );
    };

    chomp $shell;

    my ( $shell_ok, $shell_is_valid ) = Cpanel::OrDie::convert_die_to_multi_return( sub { Cpanel::Shell::is_valid_shell($shell) } );

    if ( !$shell_ok || !$shell_is_valid ) {
        $self->{'_utils'}->add_altered_item( $self->_locale()->maketext( '“[_1]” is not a valid shell on this system. This account will use the “[_2]” shell instead.', $shell, $Cpanel::Shell::NO_SHELL ) );
        $shell = $Cpanel::Shell::NO_SHELL;
    }
    elsif ( !$self->{'_utils'}->is_unrestricted_restore() ) {
        if ( $shell =~ m{jailshell} ) {
            $shell = $Cpanel::Shell::JAIL_SHELL;
        }
        elsif ( $shell =~ m{noshell} ) {
            $shell = $Cpanel::Shell::NO_SHELL;
        }
        else {
            $self->{'_utils'}->add_altered_item( $self->_locale()->maketext( '“[_1]” is not a permitted shell for restricted restore. This account will use the “[_2]” shell instead.', $shell, $Cpanel::Shell::JAIL_SHELL ) );
            $shell = $Cpanel::Shell::JAIL_SHELL;
        }
    }

    my $newuser = $self->{'_utils'}->local_username();

    my $current_shell = Cpanel::Shell::get_shell($newuser);

    if ( $shell ne $current_shell ) {
        $self->out( $self->_locale()->maketext( 'Setting the user’s shell to “[_1]” …', $shell ) );

        #TODO: error handling
        Whostmgr::Accounts::Shell::set_shell( $newuser, $shell );
    }
    else {
        $self->out( $self->_locale()->maketext( 'The user’s shell is already set to “[_1]”.', $shell ) );
    }

    AcctLock::acctunlock() or do {
        $self->warn( $self->_locale()->maketext('The system failed to unlock system utilities for shell restoration.') );
    };

    return 1;
}

*restricted_restore = \&unrestricted_restore;

1;
