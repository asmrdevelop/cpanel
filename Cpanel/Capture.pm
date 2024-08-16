package Cpanel::Capture;

# cpanel - Cpanel/Capture.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This module is here as a kludge for the Restricted Restore system.
# Its use in other contexts is discouraged, and it may be removed in 11.46.
#----------------------------------------------------------------------

use strict;
use warnings;

use Try::Tiny;

use IO::Scalar ();

sub trap_stdout {
    my ($coderef) = @_;

    my @ret;
    my $output = '';
    my $fh     = IO::Scalar->new( \$output ) || die "Failed to create IO::Scalar object";

    my $oldfh = select($fh) || die "Could not select new file handle";    ## no critic qw(Perl::Critic::Policy::InputOutput::ProhibitOneArgSelect)

    my $err;
    {
        local $Whostmgr::UI::method                      = 'hide';
        local $Whostmgr::Remote::State::HTML             = 0;
        local $Whostmgr::HTMLInterface::DISABLE_JSSCROLL = 1;
        local $SIG{'__DIE__'}                            = 'DEFAULT';

        try { @ret = $coderef->() }
        catch {
            warn $_;
            $err = $_;
        };
    }
    select($oldfh);    ## no critic qw(ProhibitOneArgSelect)

    close($fh);

    return {
        'return'   => \@ret,
        'output'   => $output,
        EVAL_ERROR => $err,
    };
}
1;
