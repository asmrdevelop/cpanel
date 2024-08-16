package Cpanel::InternalDBS;

# cpanel - Cpanel/InternalDBS.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

=pod

=head1 NAME

Cpanel::InternalDBS - Central list of internal dbs and caches

=head1 SYNOPSIS

    use Cpanel::InternalDBS;

    my $known_dbs = Cpanel::InternalDBS::get_all_dbs();

=head1 DESCRIPTION

Provide a single source of internal text databases and
caches along with their ownership and permissions
requirements that cPanel uses to optimize lookups

=head1 NOTES

This module is currently only used by Whostmgr::Accounts::DB.
In a future release scripts/updateuserdomains and
Cpanel::Userdomains::CORE will use it.

=cut

our $DEFAULT_PERMISSIONS = 0640;
our $DEFAULT_GROUP       = 'mail';
our $DEFAULT_DIR         = '/etc';

use Cpanel::ConfigFiles ();

my @DBS = (

    # Authoritative Databases (cache=0)
    { 'file' => 'remotedomains',                'format' => 'domains', 'perms' => 0644 },
    { 'file' => 'recent_authed_mail_ips',       'perms'  => 0644 },
    { 'file' => 'recent_authed_mail_ips_users', 'perms'  => 0644 },
    { 'file' => 'spammeripblocks' },
    { 'file' => 'blocked_incoming_email_countries' },
    { 'file' => 'blocked_incoming_email_country_ips' },
    { 'file' => 'blocked_incoming_email_domains' },
    { 'file' => 'trustedmailhosts' },
    { 'file' => 'skipsmtpcheckhosts' },
    { 'file' => 'backupmxhosts' },
    { 'file' => 'senderverifybypasshosts' },
    { 'file' => ( split( m{/}, $Cpanel::ConfigFiles::OUTGOING_MAIL_HOLD_USERS_FILE ) )[-1],      'format' => 'user' },
    { 'file' => ( split( m{/}, $Cpanel::ConfigFiles::OUTGOING_MAIL_SUSPENDED_USERS_FILE ) )[-1], 'format' => 'user' },
    { 'file' => ( split( m{/}, $Cpanel::ConfigFiles::NEIGHBOR_NETBLOCKS_FILE ) )[-1] },
    { 'file' => ( split( m{/}, $Cpanel::ConfigFiles::CPANEL_MAIL_NETBLOCKS_FILE ) )[-1] },
    { 'file' => ( split( m{/}, $Cpanel::ConfigFiles::GREYLIST_TRUSTED_NETBLOCKS_FILE ) )[-1] },
    { 'file' => ( split( m{/}, $Cpanel::ConfigFiles::RECENT_RECIPIENT_MAIL_SERVER_IPS_FILE ) )[-1] },
    { 'file' => 'trusted_mail_users', 'format' => 'user' },
    { 'file' => 'secondarymx',        'format' => 'domains', },
    { 'file' => 'localdomains',       'format' => 'domains', },

    # Caches managed by Cpanel::Userdomains::CORE. (cache=1)
    # The cPanel users file is the authoritative source of this data
    { 'file' => 'trueuserowners',    'key'    => 'OWNER',             'order' => 'HASH', 'format' => 'startuser', 'perms' => 0644, 'cache' => 1 },
    { 'file' => 'demodomains',       'format' => 'domains',           'cache' => 1 },
    { 'file' => 'trueuserdomains',   'key'    => 'DOMAIN',            'order' => 'REVERSE_HASH', 'format' => 'enduser',     'cache' => 1 },
    { 'file' => 'userdomains',       'key'    => 'DOMAINS',           'order' => 'HASH',         'format' => 'startdomain', 'cache' => 1 },
    { 'file' => 'domainusers',       'format' => 'startuser',         'cache' => 1 },
    { 'file' => 'userplans',         'key'    => 'PLANS',             'order' => 'HASH',         'format' => 'startuser', 'cache' => 1 },
    { 'file' => 'userbwlimits',      'key'    => 'BWLIMIT',           'order' => 'HASH',         'format' => 'startuser', 'cache' => 1 },
    { 'file' => 'demouids',          'key'    => 'DEMOUIDS',          'order' => 'REVERSE_HASH', 'format' => 'enduser',   'cache' => 1 },
    { 'file' => 'demousers',         'format' => 'user',              'cache' => 1 },
    { 'file' => 'nocgiusers',        'key'    => 'NOCGI',             'order' => 'SINGLE_HASH', 'format' => 'user',        'cache' => 1 },
    { 'file' => 'dbowners',          'key'    => 'DBOWNERS',          'order' => 'HASH',        'format' => 'startuser',   'cache' => 1 },
    { 'file' => 'email_send_limits', 'key'    => 'EMAIL_SEND_LIMITS', 'order' => 'HASH',        'format' => 'startdomain', 'cache' => 1 },
    { 'file' => 'mailbox_formats',   'key'    => 'MAILBOX_FORMATS',   'order' => 'HASH',        'format' => 'startuser',   'cache' => 1 },
    { 'file' => 'mailhelo',          'order'  => 'HASH',              'key'   => 'MAIL_HELO',   'format' => 'startdomain', 'cache' => 1 },
    { 'file' => 'mailips',           'format' => 'startdomain',       'cache' => 1 },
    { 'file' => 'userips',           'key'    => 'USER_IPS',          'order' => 'HASH', 'format' => 'startuser', 'cache' => 1 },
);

=head2 get_all_dbs()

=head3 Purpose

Return a list of all databases and caches with their attributes

=head3 Arguments

    None

=head3 Returns

    An arrayref of hashrefs in the following format

    [
        {
          'file'   => The name of the file in /etc
          'key'    => The internal key used to rebuild the db by Cpanel::Userdomains::CORE
          'order'  => The order in which the data is stored as understood by Cpanel::Userdomains::CORE::readdb
          'format' => The format in which the data is stored as understood by Whostmgr::Accounts::DB::Remove::remove_user_and_domains
          'perms'  => The unix permissions that the file must have
          'group'  => The group that the file must be owned by.  The system will use the gid of the user that matches the group
          'cache'  => Mark the file as a cache that is built by Cpanel::Userdomains::CORE
                      Files marked with this flag can safely be lost.
          'path'   => The full path to the file
        },
        .....

    ]

=cut

sub get_all_dbs {
    for (@DBS) {
        $_->{'perms'} ||= $DEFAULT_PERMISSIONS;
        $_->{'group'} ||= $DEFAULT_GROUP;
        $_->{'cache'} ||= 0;
        $_->{'path'}  ||= "$DEFAULT_DIR/$_->{'file'}";

    }
    return \@DBS;
}

1;
