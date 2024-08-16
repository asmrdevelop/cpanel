package Cpanel::Validate::EmailLocalPart;

# cpanel - Cpanel/Validate/EmailLocalPart.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

my %reserved_localparts;

sub _init () {
    my @reserved_localparts_list = qw(shadow passwd quota _archive _mainaccount _privs.json _privs.cache shadow.lock passwd.lock quota.lock _archive.lock _mainaccount.lock _privs.json.lock _privs.cache.lock cpanel);
    @reserved_localparts{@reserved_localparts_list} = (1) x scalar @reserved_localparts_list;

    {
        no warnings 'redefine';
        *_init = sub () { };
    }

    return 1;
}

# From discussions in Case 30822,
#   Supported separators
#   All characters from RFC 5322 (also 2822 and 822) are supported except for the
#   following in the local part of the address:
#     * the separator characters [+:%@]
#     * '/' - we create directories based on this name, so we can't have an illegal name
#     * [&'*|`] - since the email addresses may be passed to the shell, these characters
#                 are too dangerous to keep
#   We do not support the quoted string format, however.
sub is_valid {
    return defined $_[0] && $_[0] =~ /\A[a-zA-Z0-9!#\$\-=?^_{}~]+(?:\.[a-zA-Z0-9!#\$\-=?^_{}~]+)*\z/;
}

sub get_name_and_domain {
    my ($name) = @_;
    return unless defined $name;
    return split( /@/, $name, 2 );
}

sub is_reserved {
    my ($localpart) = @_;
    _init();
    return 1 if exists $reserved_localparts{$localpart};
    return;
}

sub list_reserved_localparts {
    _init();
    return keys %reserved_localparts;
}
1;
