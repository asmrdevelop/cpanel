package Cpanel::Services::Restart;

# cpanel - Cpanel/Services/Restart.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# forcelive is for scripts in /usr/local/cpanel/scripts
sub restartservice {
    my ( $service, $live, $forcelive, $formatter_cr, $graceful ) = @_;

    if ( !$forcelive && $Whostmgr::UI::nohtml ) { $live = 0; }
    require Cpanel::Rlimit;
    Cpanel::Rlimit::set_rlimit_to_infinity();
    Cpanel::Rlimit::set_open_files_to_maximum();
    local $ENV{'cp_security_token'} = '';
    local $ENV{'HTTP_REFERER'}      = '';

    my @cmd;

    if ( $service eq 'httpd' ) {
        @cmd = ('/usr/local/cpanel/bin/safeapacherestart');
        push @cmd, '--graceful' if $graceful;
        push @cmd, ( '--force', '--verbose' );
    }
    else {
        @cmd = ('/usr/local/cpanel/scripts/restartsrv');

        # TODO: Remove the $formatter_cr and let restartsrv know
        # that we want HTML once restartsrv is called
        # as code instead of exec
        if ( $formatter_cr && !$Whostmgr::UI::nohtml ) {
            $formatter_cr = undef;    # restartsrv knows about --html
            push @cmd, '--html';
        }

        if ($live) {
            push @cmd, '--wait', '--verbose';
        }
        push @cmd, '--graceful' if $graceful;

        push @cmd, $service;
    }

    if ($live) {
        require Cpanel::SafeRun::Object;
        require Cpanel::CPAN::IO::Callback::Write;
        my ( $program, @args ) = @cmd;
        my $saferun = Cpanel::SafeRun::Object->new(
            'program' => $program,
            'args'    => \@args,
            'stdout'  => Cpanel::CPAN::IO::Callback::Write->new(
                sub {
                    return print defined $formatter_cr ? $formatter_cr->( $_[0] ) : $_[0];
                }
            ),
            'stderr' => Cpanel::CPAN::IO::Callback::Write->new(
                sub {
                    return print defined $formatter_cr ? $formatter_cr->( $_[0] ) : $_[0];
                }
            )
        );
        return $saferun->CHILD_ERROR() ? 0 : 1;
    }
    else {
        require Cpanel::SafeRun::Errors;
        my $out = Cpanel::SafeRun::Errors::saferunallerrors(@cmd);
        return defined $formatter_cr ? $formatter_cr->($out) : $out;
    }
}

1;
