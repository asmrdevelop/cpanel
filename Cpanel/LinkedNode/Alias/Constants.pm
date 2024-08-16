package Cpanel::LinkedNode::Alias::Constants;

# cpanel - Cpanel/LinkedNode/Alias/Constants.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Alias::Constants - Constants for special linked node pseudo-aliases

=head1 SYNOPSIS

    use Cpanel::LinkedNode::Alias::Constants;

    if( $alias eq Cpanel::LinkedNode::Alias::Constants::LOCAL ) {
        # Use the local server as the “node”
    }
    elsif( $alias eq Cpanel::LinkedNode::Alias::Constants::EXISTING ) {
        # Use the existing alias as the node
    }

    if( grep { $alias eq $_ } Cpanel::LinkedNode::Alias::Constants::ALL_PSEUDO_ALIASES ) {
        # Treat the alias as a special pseudo-alias
    }

=head1 DESCRIPTION

This module defines constants that are used for special behavior when specifying linked
node aliases.

=cut

use constant {
    LOCAL    => ".local",
    EXISTING => ".existing",
};

use constant ALL_PSEUDO_ALIASES => ( LOCAL, EXISTING );

1;
