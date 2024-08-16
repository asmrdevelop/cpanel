package Cpanel::Dovecot::Config;

# cpanel - Cpanel/Dovecot/Config.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Dovecot::Config - Configuration data for dovecot.

=head1 SYNOPSIS

    use Cpanel::Dovecot::Config;

    my @mailbox_formats_for_sync = keys %Cpanel::Dovecot::Config::KNOWN_FORMATS;

=cut

our %KNOWN_FORMATS = (
    'detect'  => 1,
    'mbox'    => 1,
    'mdbox'   => 1,
    'maildir' => 1,
);

1;
