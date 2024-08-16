package Cpanel::Config::CpUser::Defaults;

# cpanel - Cpanel/Config/CpUser/Defaults.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::CpUser::Defaults

=head1 DESCRIPTION

This module holds cpuser file default values.

=cut

#----------------------------------------------------------------------

use Cpanel::SSL::DefaultKey::Constants ();

#----------------------------------------------------------------------

# Since these are usually included in another hash we make an array here
# instead of a hash.
our @DEFAULTS_KV = (
    'BWLIMIT'              => 'unlimited',
    'CHILD_WORKLOADS'      => q<>,
    'DEADDOMAINS'          => undef,
    'DEMO'                 => 0,
    'DOMAIN'               => '',
    'DOMAINS'              => undef,
    'FEATURELIST'          => 'default',
    'HASCGI'               => 0,
    'HASDKIM'              => 0,
    'HASSPF'               => 0,
    'IP'                   => '127.0.0.1',
    'MAILBOX_FORMAT'       => 'maildir',                                         #keep in sync with cpconf
    'MAX_EMAILACCT_QUOTA'  => 'unlimited',
    'MAXADDON'             => 0,
    'MAXFTP'               => 'unlimited',
    'MAXLST'               => 'unlimited',
    'MAXPARK'              => 0,
    'MAXPOP'               => 'unlimited',
    'MAXSQL'               => 'unlimited',
    'MAXSUB'               => 'unlimited',
    'OWNER'                => 'root',
    'PLAN'                 => 'undefined',
    'RS'                   => '',
    'STARTDATE'            => '0000000000',
    'MAXPASSENGERAPPS'     => 4,
    'SSL_DEFAULT_KEY_TYPE' => Cpanel::SSL::DefaultKey::Constants::USER_SYSTEM,
);

1;
