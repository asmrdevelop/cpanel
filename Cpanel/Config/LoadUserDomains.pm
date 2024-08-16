package Cpanel::Config::LoadUserDomains;

# cpanel - Cpanel/Config/LoadUserDomains.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig             ();
use Cpanel::Config::LoadUserDomains::Count ();
use Cpanel::Server::Type                   ();

=encoding utf-8

=head1 NAME

Cpanel::Config::LoadUserDomains

=head1 THE DIFFERENCE BETWEEN USERDOMAINS AND TRUEUSERDOMAINS

=head2 userdomains (stored at /etc/userdomains)

Every domain, including addon domains and subdomains, belonging to each user,
listed according to ownership.

I<Important note>: The userdomains list does not have a one-to-one correspondence of
keys to values. Therefore, it is important to use either the $reverse or the $usearr
flag when querying userdomains. Otherwise, a single key/value pair will win out for
each user and cause the other records to be omitted from the list.

=head2 trueuserdomains (stored at /etc/trueuserdomains)

Only the primary domain for each user, listed according to ownership.
In other words, this is what would appear in $Cpanel::CPDATA{'DNS'}
for each user.

=head2 key/value order

Another difference between the two is the key/value order used by default by the
load... functions. See the documentation below for details.

=head1 FUNCTIONS

=head2 loaduserdomains

Loads the userdomains file.

=head3 Arguments

$conf_ref - Hash ref - (Optional) A hash into which the data will be loaded. If not
specified, a new one will be created. In either case, the same variable will also be
returned by the function.

$reverse - Boolean - Flips the mapping of keys to values in the output. When false or
unspecified, the response will be formatted as USERNAME => DOMAIN. When true, the
response will be formatted as DOMAIN => USERNAME.

I<Important note>: The loaduserdomains and loadtrueuserdomains functions do not have
the same default orientation of keys and values. While the loaduserdomains function
by default maps users to domains, the loadtrueuserdomains function by default maps
domains to users.


$usearr - Boolean - Group the values into an array ref for each key. This allows you to
represent more than one value per key.

=head3 Returns

This function returns a hash ref with a key/value mapping of users to domains
or domains to users, depending on which arguments were passed.

=cut

sub loaduserdomains {
    my ( $conf_ref, $reverse, $usearr ) = @_;
    $conf_ref = Cpanel::Config::LoadConfig::loadConfig(
        Cpanel::Config::LoadUserDomains::Count::_userdomains(),
        $conf_ref,
        ': ',     # We write the file so there is no need to match stray spaces
        '0E0',    # Avoid looking for comments since there will not be any
        0,        # reverse
        1,        # allow_undef_values since there will not be any
        {
            'use_reverse'          => $reverse ? 0 : 1,
            'skip_keys'            => ['nobody'],
            'use_hash_of_arr_refs' => ( $usearr || 0 ),
        }
    );
    if ( !defined($conf_ref) ) {
        $conf_ref = {};
    }
    return wantarray ? %{$conf_ref} : $conf_ref;
}

=head2 loadtrueuserdomains

Loads the trueuserdomains file.

=head3 Arguments

$conf_ref - Hash ref - (Optional) A hash into which the data will be loaded. If not
specified, a new one will be created. In either case, the same variable will also be
returned by the function.

$reverse - Boolean - Flips the mapping of keys to values in the output. When false or
unspecified, the response will be formatted as DOMAIN => USERNAME. When true, the
response will be formatted as USERNAME => DOMAIN.

$ignore_limit - Boolean - Instructs this function to return the true number
of accounts on the system rather than limiting itself to the max number of
users that a server’s license allows.

I<Important note>: The loaduserdomains and loadtrueuserdomains functions do not have
the same default orientation of keys and values. While the loaduserdomains function
by default maps users to domains, the loadtrueuserdomains function by default maps
domains to users.

=head3 Returns

This function returns a hash ref with a key/value mapping of users to domains
or domains to users, depending on which arguments were passed.

=cut

sub loadtrueuserdomains {
    my ( $conf_ref, $reverse, $ignore_limit ) = @_;
    $conf_ref = Cpanel::Config::LoadConfig::loadConfig(
        ( $reverse ? Cpanel::Config::LoadUserDomains::Count::_domainusers() : Cpanel::Config::LoadUserDomains::Count::_trueuserdomains() ),
        $conf_ref,
        ': ',     # We write the file so there is no need to match stray spaces
        '0E0',    # Avoid looking for comments since there will not be any
        0,        # reverse
        1,        # allow_undef_values since there will not be any
        { 'limit' => ( $ignore_limit ? 0 : Cpanel::Server::Type::get_max_users() ) }
    );
    if ( !defined($conf_ref) ) {
        $conf_ref = {};
    }
    return wantarray ? %{$conf_ref} : $conf_ref;
}

# avoid warning used once from updatenow.static
*counttrueuserdomains = *counttrueuserdomains = *Cpanel::Config::LoadUserDomains::Count::counttrueuserdomains;

1;
