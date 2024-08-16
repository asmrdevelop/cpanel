
# cpanel - Cpanel/LinkedNode/Alias.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::LinkedNode::Alias;

use strict;
use warnings;

# Exposed for testing
our $MAX_ALIAS_LENGTH = 50;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Alias - Utility methods for linked node aliases

=head1 SYNOPSIS

    use Cpanel::LinkedNode::Alias;

    Cpanel::LinkedNode::Alias::validate_linked_node_alias_or_die( $alias_to_check );

=head1 DESCRIPTION

This module contains utility methods for working with the aliases for
linked server nodes at both a root and user-level

=head1 FUNCTIONS

=head2 validate_linked_node_alias_or_die( $alias_to_check )

Validates a string to see if it can be used as an alias for a linked node

=over

=item Input

=over

=item C<STRING>

The string to validate

=back

=item Output

=over

This function returns empty on success, dies otherwise

=back

=back

=cut

sub validate_linked_node_alias_or_die {

    my ($alias) = @_;

    if ( !length $alias ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'alias' ] );
    }
    elsif ( $alias =~ tr/0-9a-zA-Z\-_//c ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'InvalidParameter', 'The alias “[_1]” is invalid. The alias can only contain alphanumeric, dash, and underscore characters.', [$alias] );
    }
    elsif ( length $alias > $MAX_ALIAS_LENGTH ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'InvalidParameter', 'The alias cannot be longer than [quant,_1,character,characters].', [$MAX_ALIAS_LENGTH] );
    }

    return;
}

1;
