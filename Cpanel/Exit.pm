package Cpanel::Exit;

# cpanel - Cpanel/Exit.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# A base class.
#----------------------------------------------------------------------

use strict;

# code = The exit code to pass to exit
sub exit_with_stdout_closed_first {
    my ($code) = @_;
    close(STDOUT);    # We close STDOUT right before global destruction so cpsrvd
                      # can send the end of the response without having to wait for global
                      # destruction to close it after it has torn down everything else.
                      # This provides a noticable speedup in cpsrvd response time when we
                      # are running a binary that take a while to unload from memory
                      #
                      # For more information, see subprocess_handler in cpsrvd
                      #
    exit( $code || 0 );
}

1;
