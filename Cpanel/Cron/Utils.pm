package Cpanel::Cron::Utils;

# cpanel - Cpanel/Cron/Utils.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Autodie            ();
use Cpanel::PwCache::Get       ();
use Cpanel::Config::LoadConfig ();
use Cpanel::Exception          ();
use Cpanel::JailSafe           ();
use Cpanel::Debug              ();
use Cpanel::SafeRun::Object    ();
use Cpanel::Shell              ();

#
# Commands that need a full shell must be listed here
#
# *All arugments must be included in the key*.  For example
# if you wanted to whitelist
# /usr/local/cpanel/bin/process_ssl_pending_queue with the --verbose flag
# the key must be "/usr/local/cpanel/bin/process_ssl_pending_queue --verbose"
#
my %SHELL_APPLIST = ( '/usr/local/cpanel/bin/process_ssl_pending_queue' => '/bin/bash' );

our $CRONTAB_SHELL_FILE = '/var/cpanel/crontabshell';

sub fetch_user_crontab {
    my ($username) = @_;

    my @u_args = length($username) ? ( -u => $username ) : ();

    my $tab;
    try {
        $tab = run_crontab( args => [ @u_args, '-l' ] );
    }
    catch {
        local $@ = $_;

        die if !try { $_->isa('Cpanel::Exception::ProcessFailed::Error') };
        die if $_->get('error_code') != 1;

        $@ = $_;

        die if $_->get('stderr') !~ m<\Ano crontab for \Q$username\E>;
    };

    return $tab ? $tab->stdout() : q<>;
}

sub save_user_crontab {
    my ( $username, $crontab ) = @_;

    #Reject for root because root doesn’t need fix_user_crontab().
    if ( $username eq 'root' ) {
        die 'Use save_root_crontab() for root!';
    }

    fix_user_crontab( $username, \$crontab );

    run_crontab(
        args  => [ -u => $username, '-' ],
        stdin => \$crontab,
    );

    return;
}

sub save_root_crontab {
    my ($crontab) = @_;

    run_crontab(
        args  => [ -u => 'root', '-' ],
        stdin => \$crontab,
    );

    return;
}

sub run_crontab {
    my (%args) = @_;

    my $bin = _find_crontab_bin();

    _check_crontab_bin_mode($bin) if !$>;

    local $ENV{'LC_ALL'} = 'C';    # try to avoid before_exec because it prevents fast spawn

    my $run = Cpanel::SafeRun::Object->new(
        program => $bin,
        %args,
    );

    try {
        $run->die_if_error();
    }
    catch {
        local $@ = $_;

        die if !try { $_->isa('Cpanel::Exception::ProcessFailed::Error') };

        if ( $_->get('stderr') && $_->get('stderr') =~ m<user `([^']+)' unknown> ) {
            die Cpanel::Exception::create( 'UserNotFound', 'The user “[_1]” does not exist.', [$1] );
        }

        my $is_listing_crontab = 0;
        if ( $args{'args'} && grep { $_ eq '-l' } @{ $args{'args'} } ) {
            $is_listing_crontab = 1;
        }

        if ( $is_listing_crontab && $_->get('stderr') && $_->get('stderr') =~ m<no crontab>i ) {

            # centos 7 exits with a status of
            # 1 when there is no crontab for a user
        }
        else {
            die;
        }
    };

    return $run;
}

#This assumes that the username is a valid one.
#The payload on success indicates whether the crontab buffer changed or not.
sub fix_user_crontab {
    my ( $username, $crontab_sr ) = @_;

    my $cron_shell = get_user_cron_shell($username);

    my $changed = enforce_crontab_shell( $crontab_sr, $cron_shell );

    if ( !$changed && substr( $$crontab_sr, -1 ) ne '/' ) {
        $$crontab_sr .= $/;
        $changed = 1;
    }

    return $changed;
}

sub get_user_cron_shell {
    my ($user) = @_;

    my $pw_shell = Cpanel::PwCache::Get::getshell($user);

    # /etc/passwd is authoritative here,
    # not the cpuser file. (sorry)
    if ( $pw_shell && $pw_shell =~ m/\/(?:no|jail)shell/ ) {
        return $Cpanel::Shell::JAIL_SHELL;
    }

    my $cronshell;

    # Allow admins to specify a default SHELL setting
    if ( Cpanel::Autodie::exists($CRONTAB_SHELL_FILE) ) {

        #TODO: Improve error checking of loadConfig() (or replace it!)
        my $cron_shell_ref = Cpanel::Config::LoadConfig::loadConfig($CRONTAB_SHELL_FILE);
        $cronshell = $cron_shell_ref->{'SHELL'};
    }

    $cronshell ||= $pw_shell;

    return $cronshell;
}

sub validate_cron_shell_or_die {
    my ($cronshell) = @_;

    Cpanel::Autodie::exists($cronshell);

    if ( !-x _ ) {
        die Cpanel::Exception->create( "The [asis,cron] shell “[_1]” is not executable. This likely indicates a faulty system configuration.", [$cronshell] );
    }

    if ( !Cpanel::Shell::is_valid_shell($cronshell) ) {
        die Cpanel::Exception->create( "The [asis,cron] shell “[_1]” is not a valid shell on this system.", [$cronshell] );
    }

    return;
}

sub CORRECT_CRONTAB_BIN_PERMISSIONS {

    # Cent6 -> rpm -v -v -v -ql  cronie     : 04755
    # Cent7 -> rpm -v -v -v -ql  cronie     : 04755
    return 04755;
}

#FOR TESTING
sub _find_crontab_bin {
    my $bin = Cpanel::JailSafe::get_system_binary('crontab') or do {
        die Cpanel::Exception->new('The system failed to find the “[_1]” command.');
    };

    return $bin;
}

sub _check_crontab_bin_mode {
    my ($bin) = @_;

    my $mode        = ( Cpanel::Autodie::stat($bin) )[2] & 07777;
    my $expect_mode = CORRECT_CRONTAB_BIN_PERMISSIONS();

    if ( $mode != $expect_mode ) {
        Cpanel::Debug::log_warn( sprintf "“$bin” should be set to 0%o permissions but is set to 0%o instead. The system will attempt to correct this now.", $expect_mode, $mode );

        try {
            Cpanel::Autodie::chmod( $expect_mode, $bin );
        }
        catch {
            local $@ = $_;
            warn;
        };
    }

    return 1;
}

#Return value indicates whether the contents changed.
sub enforce_crontab_shell {
    my ( $contents_sr, $enforced_shell ) = @_;

    if ( !length $enforced_shell ) {
        die "enforce_crontab_shell requires a shell to enforce";
    }

    my @crontab = split( m{\r?\n}, $$contents_sr );

    my ( $modified, $command, $last_seen_shell, $last_line_was_shell );
    my @new_crontab;

    foreach my $line (@crontab) {
        if ( !length $line || $line =~ m{^[ \t]*$} ) {    # An empty line
            $modified = 1;
            next;
        }
        elsif ( $line =~ m{^[ \f\r\t\v]*['"]?SHELL['"]?[ \f\r\t\v]*=[ \f\r\t\v]*['"]?([^'"]*)} ) {    # Shell settings
            my $requested_shell = $1 || $enforced_shell;

            if ( ( $requested_shell eq $enforced_shell ) || grep { $requested_shell eq $SHELL_APPLIST{$_} } keys %SHELL_APPLIST ) {
                $last_seen_shell = $requested_shell;
            }
            else {
                $last_seen_shell = $enforced_shell;
                $modified        = 1;
            }

            $last_line_was_shell = 1;
            next;
        }
        elsif ( $line =~ m{^[ \f\r\t\v]*#} || $line =~ m{^[ \f\r\t\v]*['"]?[^=]+['"]?[ \f\r\t\v]*=} ) {    # Any variable or comment line
            push @new_crontab, $line;
            $last_line_was_shell = 0;
        }
        else {                                                                                             # A crontab line
            $command = ( split( /\s+/, $line, 6 ) )[5];

            my $shell_to_set = ( length $command && $SHELL_APPLIST{$command} ) ? $SHELL_APPLIST{$command} : $enforced_shell;

            if ( !length $last_seen_shell || $last_seen_shell ne $shell_to_set ) {

                # Only validate new shells
                validate_cron_shell_or_die($shell_to_set);

                $modified = 1;
            }

            push @new_crontab, ( qq{SHELL="$shell_to_set"}, $line, '' );
            $last_line_was_shell = 0;
        }
    }

    return 0 if !$modified && !$last_line_was_shell;

    $$contents_sr = join( "\n", @new_crontab ) . "\n";

    return 1;
}

1;
