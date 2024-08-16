package Cpanel::Exception::ProcessFailed::Error;

# cpanel - Cpanel/Exception/ProcessFailed/Error.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE NOTE NOTE NOTE: Do NOT use this class for exec() failures;
# that is what IO::ExecError is for.
#
# This class is for when an external process exits in error. It should
# **NOT** be used for when the process exits because of a signal. (Perl
# tells you the difference via “$?”.) Use ProcessFailed::Signal for that.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Exception::ProcessFailed );

use Cpanel::LocaleString ();

#metadata parameters:
#   error_code      (required, number; e.g., the value of $? >> 8)
#   process_name    (optional)
#   pid             (optional)
#
sub _default_phrase {
    my ($self) = @_;

    my ( $error_code, $name, $pid, $stdout, $stderr ) = map { $self->get($_) } qw(
      error_code
      process_name
      pid
      stdout
      stderr
    );

    $stderr ||= '';

    die "Need “error_code”!" if !length $error_code;

    if ( length $name ) {
        if ( length $pid ) {
            return Cpanel::LocaleString->new(
                '“[_1]” (process [asis,ID] [_2]) reported error code “[_3]” when it ended: [_4]',
                $name,
                $pid,
                $error_code,
                $stderr
            );
        }

        return Cpanel::LocaleString->new(
            '“[_1]” reported error code “[_2]” when it ended: [_3]',
            $name,
            $error_code,
            $stderr,
        );
    }

    if ( length $pid ) {
        return Cpanel::LocaleString->new(
            'The subprocess with [asis,ID] “[_1]” reported error code “[_2]” when it ended: [_3]',
            $pid,
            $error_code,
            $stderr,
        );
    }

    return Cpanel::LocaleString->new(
        'A subprocess reported error code “[_1]” when it ended: [_2]',
        $error_code,
        $stderr,
    );
}

1;
