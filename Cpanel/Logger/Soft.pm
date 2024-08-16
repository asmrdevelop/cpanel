package Cpanel::Logger::Soft;

# cpanel - Cpanel/Logger/Soft.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::Logger::Soft

=head1 SYNOPSIS

    use Cpanel::Logger::Soft ();

    # log the event and send a notification on sandboxes only
    Cpanel::Logger::Soft::deprecated( "Do not use this software on a sandbox" );

=head1 DESCRIPTION

This is a special log level used to notify developers on sandbox to avoid
using some code path (API calls, ...).

This has no actions on customer boxes or compiled binaries.

=cut

use strict;
use warnings;

use Cpanel::Binary ();
our $logger;

=head1 FUNCTIONS

=head2 deprecated

Only notify and log warning on uncompiled binaries on a sandbox.

=cut

BEGIN {
    if ( Cpanel::Binary::is_binary() ) {    # disable the notice function on compiled code
        *deprecated = sub { }               # only design to warn on a sandbox which should not run compiled code
    }
    else {
        *deprecated = sub {
            my ($msg) = @_;

            require Cpanel::Logger;
            return unless Cpanel::Logger::is_sandbox();

            return if -e '/var/cpanel/suppress_deprecated_log_messages';

            $logger //= Cpanel::Logger->new();

            my $log = {
                'message'   => $msg,
                'level'     => 'soft_deprecated',
                'output'    => 0,
                'service'   => $logger->find_progname(),
                'backtrace' => $logger->get_backtrace(),
                'die'       => 0,
            };

            $logger->notify( 'soft_deprecated', $log );
            $logger->logger($log);

            return;

        }
    }
}

1;
