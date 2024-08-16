package Cpanel::FileUtils::Permissions::String;

# cpanel - Cpanel/FileUtils/Permissions/String.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();

=encoding utf-8

=head1 NAME

Cpanel::FileUtils::Permissions::String

=head1 SYNOPSIS

my $permission_string = 'rwxr-xr-x';
my $oct_perms = Cpanel::FileUtils::Permissions::String::str2oct($permission_string);

my $perm = bits2oct(user_read => 1, user_write => 1, user_execute => 1, group_read => 1);
assert($perm == '740');

$perm = bits2oct(user_read => 1, group_read => 1);
assert($perm == '440');

$perm = bits2oct(user_read => 1);
assert($perm == '400');

$perm = bits2oct(user_write => 1);
assert($perm == '200');

$perm = bits2oct(user_execute => 1);
assert($perm == '100');

=head1 DESCRIPTION

This module is used to manipulate or parse file permission strings as received by a tar listing.

=head1 FUNCTIONS

=head2 str2oct( STRING_PERMS )

This function takes a string representation of file permissions and converts it to the octal representation.

=head3 Arguments

=over 4

=item STRING_PERSM    - SCALAR - The string representation of filesystem permissions, ex. 'rwxr-xr-x'

=back

=head3 Returns

An octal representation of the file permissions. ex. 0755

=head3 Exceptions

InvalidParameter may be thrown if the string passed in is not valid filesystem permissions.

=cut

sub str2oct {
    my ($string) = @_;
    if ( length $string > 9 ) {
        $string = substr( $string, 1, 9 );
    }
    if ( $string !~ /^[rwxsStT-]{9}$/ ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” was given an invalid permissions string: [_2]', [ ( caller(0) )[3], $string ] );
    }
    my @str_perms = (
        substr( $string, 0, 3 ),    # user
        substr( $string, 3, 3 ),    # group
        substr( $string, 6, 3 ),    # global
    );

    my $special_perm = 0;
    my $oct_perms;
    my @perm_sets = ( 'user', 'group', 'global' );
    foreach my $perm_grouping_string (@str_perms) {
        my $perm_set = shift @perm_sets;

        my $value = 0;
        my ( $read, $write, $execute ) = split( '', $perm_grouping_string );

        $value += 4 if $read eq 'r';
        $value += 2 if $write eq 'w';
        $value += 1 if $execute eq 'x' || $execute eq 's' || $execute eq 't';
        if ( $execute eq 's' || $execute eq 'S' || $execute eq 'T' || $execute eq 't' ) {
            if ( $perm_set eq 'user' ) {
                $special_perm += 4;
            }
            elsif ( $perm_set eq 'group' ) {
                $special_perm += 2;
            }
            elsif ( $perm_set eq 'global' ) {
                $special_perm += 1;
            }
        }
        $oct_perms .= $value;
    }
    if ($special_perm) {
        return $special_perm . $oct_perms;
    }
    else {
        return 0 . $oct_perms;
    }

}

=head2 bit2oct(...)

Convert individual file permission arguments into the octal file permission format.

=head3 ARGUMENTS

=over

=item - user_read - Boolean

When 1 turn on read bit, when 0 turn off read bit.

=item - user_write - Boolean

When 1 turn on write bit, when 0 turn off write bit.

=item - user_execute - Boolean

When 1 turn on execute bit, when 0 turn off execute bit.

=item - group_read - Boolean

When 1 turn on read bit, when 0 turn off read bit.

=item - group_write - Boolean

When 1 turn on write bit, when 0 turn off write bit.

=item - group_execute - Boolean

When 1 turn on execute bit, when 0 turn off execute bit.

=item - global_read - Boolean

When 1 turn on read bit, when 0 turn off read bit.

=item - global_write - Boolean

When 1 turn on write bit, when 0 turn off write bit.

=item - global_execute - Boolean

When 1 turn on execute bit, when 0 turn off execute bit.

=back

=head3 RETURNS

=over

=item string

The octal representation of the requested permission flags.

=back

=head3 THROWS

=over

=item When the parameter name is not recognized.

=back

=cut

sub bits2oct {
    my %args = @_;
    my (@scopes) = ( 0, 0, 0 );
    foreach my $key ( keys %args ) {
        my ( $perm_set, $perm ) = split( '_', $key );
        my $pos;
        if ( $perm_set eq 'user' ) {
            $pos = 0;
        }
        elsif ( $perm_set eq 'group' ) {
            $pos = 1;
        }
        elsif ( $perm_set eq 'global' ) {
            $pos = 2;
        }
        else {
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a recognized bit name.', [$key] );
        }

        if ( $perm eq 'read' ) {
            $scopes[$pos] += 4 if $args{$key};
        }
        elsif ( $perm eq 'write' ) {
            $scopes[$pos] += 2 if $args{$key};
        }
        elsif ( $perm eq 'execute' ) {
            $scopes[$pos] += 1 if $args{$key};
        }
        else {
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a recognized bit name.', [$key] );
        }
    }
    return join( '', @scopes );
}

1;
