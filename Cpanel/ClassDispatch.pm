package Cpanel::ClassDispatch;

# cpanel - Cpanel/ClassDispatch.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::ClassDispatch

=head1 SYNOPSIS

    my @ret = Cpanel::ClassDispatch::dispatch(
        $object,

        Class1 => sub { .. },
        'Other::Class' => sub { .. },
    );

=head1 DESCRIPTION

This module implements a simple dispatch for when you need to execute
one of several actions depending on a given object’s class.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 ? = dispatch( $OBJECT, @CLASS_ACTION_KV )

Executes an action depending on $OBJECT’s class.

Specifically: for each pair ( $class => $todo ) in @CLASS_ACTION_KV,
if C<$OBJECT-E<gt>isa($class)>, then C<dispatch()>’s return value is the
return from C<$todo-E<gt>()>.

Note that this honors subclassing. So if C<Dog> extends C<Animal>, and you
do:

    Cpanel::ClassDispatch::dispatch(
        $dog,

        Animal => sub { .. },
        Dog => sub { .. },
    );

… then the first callback will be called. As a result, B<ORDER> B<MATTERS>
for @CLASS_ACTION_KV.

If no C<$class>es match $OBJECT, then an exception is thrown.

=cut

sub dispatch ( $thing, @class_todo_pairs ) {
    die 'must have even args list!' if @class_todo_pairs % 2;

    my $i = 0;

    while ( $i < @class_todo_pairs ) {
        if ( $thing->isa( $class_todo_pairs[$i] ) ) {
            return $class_todo_pairs[ 1 + $i ]->();
        }

        $i += 2;
    }

    die "No class matched $thing!";
}

1;
