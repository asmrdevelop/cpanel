package Cpanel::Exception::ProcessFailed::Signal;

# cpanel - Cpanel/Exception/ProcessFailed/Signal.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::ProcessFailed );

use Cpanel::Config::Constants::Perl ();
use Cpanel::LocaleString            ();

#metadata parameters:
#   signal_code     (required, number)
#   process_name    (optional)
#   pid             (optional)
#
sub _default_phrase {
    my ($self) = @_;

    my ( $sigcode, $name, $pid, $stdout, $stderr ) = map { $self->get($_) } qw(
      signal_code
      process_name
      pid
      stdout
      stderr
    );

    $stderr ||= '';

    die "Need “signal_code”!" if !length $sigcode;

    my $signame = $Cpanel::Config::Constants::Perl::SIGNAL_NAME{$sigcode};

    if ( length $name ) {
        if ( length $pid ) {
            return Cpanel::LocaleString->new(
                '“[_1]” (process [asis,ID] [_2]) ended prematurely because it received the “[_3]” ([_4]) signal: [_5]',
                $name,
                $pid,
                $signame,
                $sigcode,
                $stderr,
            );
        }

        return Cpanel::LocaleString->new(
            '“[_1]” ended prematurely because it received the “[_2]” ([_3]) signal: [_4]',
            $name,
            $signame,
            $sigcode,
            $stderr
        );
    }

    if ( length $pid ) {
        return Cpanel::LocaleString->new(
            'The subprocess with [asis,ID] “[_1]” ended prematurely because it received the “[_2]” ([_3]) signal: [_4]',
            $pid,
            $signame,
            $sigcode,
            $stderr
        );
    }

    return Cpanel::LocaleString->new(
        'A subprocess ended prematurely because it received the “[_1]” ([_2]) signal: [_3]',
        $signame,
        $sigcode,
        $stderr
    );
}

sub signal_name {
    my ($self) = @_;

    return $Cpanel::Config::Constants::Perl::SIGNAL_NAME{ $self->get('signal_code') };
}

1;
