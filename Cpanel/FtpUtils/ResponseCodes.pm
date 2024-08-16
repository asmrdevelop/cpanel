package Cpanel::FtpUtils::ResponseCodes;

# cpanel - Cpanel/FtpUtils/ResponseCodes.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

my $response_codes;

# See RFC 959
sub _init_response_codes {
    return $response_codes if keys %$response_codes;

    $response_codes = {

        # Net::Cmd closed the connection
        '000' => 'The connection closed unexpectedly.',

        # Positive preliminary reply
        100 => q{The requested action is being initiated; expect another reply before proceeding with a new command.},
        110 => q{Restart marker reply. In this case, the text is exact and not left to the particular implementation; it must read: MARK yyyy = mmmm Where yyyy is User-process data stream marker, and mmmm server's equivalent marker (note the spaces between markers and "=").},
        120 => q{Service ready in nnn minutes.},
        125 => q{Data connection already open; transfer starting.},
        150 => q{File status okay; about to open data connection.},

        # Positive completion reply
        200 => q{Command okay.},
        202 => q{Command not implemented, superfluous at this site.},
        211 => q{System status, or system help reply.},
        212 => q{Directory status.},
        213 => q{File status.},
        214 => q{Help message. On how to use the server or the meaning of a particular non-standard command.  This reply is useful only to the human user.},
        215 => q{NAME system type. Where NAME is an official system name from the list in the Assigned Numbers document.},
        220 => q{Service ready for new user.},
        221 => q{Service closing control connection. Logged out if appropriate.},
        225 => q{Data connection open; no transfer in progress.},
        226 => q{Closing data connection. Requested file action successful (for example, file transfer or file abort).},
        227 => q{Entering Passive Mode (h1,h2,h3,h4,p1,p2).},
        230 => q{User logged in, proceed.},
        250 => q{Requested file action okay, completed.},
        257 => q{"PATHNAME" created.},

        # Positive intermediate reply
        300 => q{The command has been accepted, but the requested action is being held in abeyance, pending receipt of further information.},
        331 => q{User name okay, need password.},
        332 => q{Need account for login.},
        350 => q{Requested file action pending further information.},

        # Transient negative completion reply
        400 => q{The command was not accepted and the requested action did not take place, but the error condition is temporary and the action may be requested again.},
        421 => q{Service not available, closing control connection. This may be a reply to any command if the service knows it must shut down.},
        425 => q{Can't open data connection.},
        426 => q{Connection closed; transfer aborted.},
        450 => q{Requested file action not taken. File unavailable (e.g., file busy).},
        451 => q{Requested action aborted: local error in processing.},
        452 => q{Requested action not taken. Insufficient storage space in system.},

        # Permanent negative completion reply
        500 => q{Syntax error, command unrecognized. This may include errors such as command line too long.},
        501 => q{Syntax error in parameters or arguments.},
        502 => q{Command not implemented.},
        503 => q{Bad sequence of commands.},
        504 => q{Command not implemented for that parameter.},
        530 => q{Not logged in.},
        532 => q{Need account for storing files.},
        550 => q{Requested action not taken. File unavailable (e.g., file not found, no access).},
        551 => q{Requested action aborted: page type unknown.},
        552 => q{Requested file action aborted. Exceeded storage allocation (for current directory or dataset).},
        553 => q{Requested action not taken. File name not allowed.},
    };

    return $response_codes;
}

sub get_response_text {
    my ($code) = @_;

    _init_response_codes();

    return $response_codes->{$code} if exists $response_codes->{$code};

    return 'Unknown response.' if length $code != 3;

    my $section_code = substr( $code, 0, 1 ) . '00';

    return $response_codes->{$section_code} if exists $response_codes->{$section_code};
    return 'Unknown response.';
}

1;
