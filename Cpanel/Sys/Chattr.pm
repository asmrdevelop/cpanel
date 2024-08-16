package Cpanel::Sys::Chattr;

# cpanel - Cpanel/Sys/Chattr.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

=pod

=encoding utf8

=head1 NAME

Cpanel::Sys::Chattr - Pure perl implementation of chattr

=head1 DESCRIPTION

This module avoids the need to launch the external chattr binary. It instead uses
an ioctl() call on a filehandle to achieve the same result.

=head1 SYNOPSIS

    open(my $fh, '<', '/usr/local/cpanel/logs/error_log');

    Cpanel::Sys::Chattr::set_attribute($fh, 'NOATIME');
    Cpanel::Sys::Chattr::remove_attribute($fh, 'IMMUTABLE');
    my $append_only = Cpanel::Sys::Chattr::get_attribute($fh, 'APPEND');

=cut

# This uses the same basic logic as Cpanel::Syscall's lookup table.
# Any new IOCTL constants that are added to this table should take
# the form:
# CONSTANT_NAME      64bit value

my %NAME_TO_NUMBER = qw(
  FS_IOC_GETFLAGS    2148034049
  FS_IOC_SETFLAGS    1074292226
  FS_SECRM_FL                 1
  FS_UNRM_FL                  2
  FS_COMPR_FL                 4
  FS_SYNC_FL                  8
  FS_IMMUTABLE_FL            16
  FS_APPEND_FL               32
  FS_NODUMP_FL               64
  FS_NOATIME_FL             128
);

=head1 FUNCTIONS

=head2 set_attribute( FH, ATTR )

Given an already-open filehandle FH, set the attribute ATTR on the file.

=cut

sub set_attribute {
    my ( $fh, $attribute ) = @_;

    my $attribute_number   = name_to_number("FS_${attribute}_FL");
    my $current_attributes = _get_attributes($fh);
    return unless defined $current_attributes;
    return 1 if ( $current_attributes & $attribute_number );
    return _set_attributes( $fh, $current_attributes | $attribute_number );
}

=head2 remove_attribute( FH, ATTR )

Given an already-open filehandle FH, remove the attribute ATTR from the file.

=cut

sub remove_attribute {
    my ( $fh, $attribute ) = @_;

    my $attribute_number   = name_to_number("FS_${attribute}_FL");
    my $current_attributes = _get_attributes($fh);
    return 1 unless ( $current_attributes & $attribute_number );
    return _set_attributes( $fh, $current_attributes & ~$attribute_number );
}

=head2 get_attribute( FH, ATTR )

Given an already-open filehandle FH, retrieve the current state of the attribute ATTR.

=cut

sub get_attribute {
    return _get_attributes( $_[0] ) & name_to_number("FS_$_[1]_FL");
}

# $fh = $_[0]
sub _get_attributes {
    my $res = pack 'L', 0;
    return unless defined ioctl( $_[0], name_to_number('FS_IOC_GETFLAGS'), $res );
    return scalar unpack 'L', $res;
}

sub _set_attributes {
    my ( $fh, $flags ) = @_;
    my $flag = pack 'L', $flags;
    return ioctl( $fh, name_to_number('FS_IOC_SETFLAGS'), $flag );
}

sub name_to_number {
    return $NAME_TO_NUMBER{ $_[0] } || _die_unknown_constant( $_[0] );
}

sub _die_unknown_constant {
    my $name = shift;
    die "Unknown ioctl constant: $name";
}

=head1 SUPPORTED ATTRIBUTES

These are the attributes whose flag values from /usr/include/linux/fs.h are currently supported by Cpanel::Sys::Chattr.

=head2 Common

=over

=item 'IMMUTABLE' - Immutable - Not even root can edit or delete the file until this attribute is removed.

=item 'APPEND' - Append-only - Users with permission can continue to append to the file, but they cannot
truncate it.

=item 'NOATIME' - Do not update access time - This is sometimes used as an attempt to optimize performance, but
an entire filesystem may also be mounted with access time updates disabled, in which case this attribute is
rendered pointless.

=back

=head2 Uncommon

=over

=item 'SECRM' - Secure deletion

=item 'UNRM' - Undelete

=item 'COMPR' - Compress file

=item 'SYNC' - Synchronous updates

=item 'NODUMP' - Do not dump the file

=back

B<Important note>: Being supported by the module does not necessarily mean that the attribute is supported by
the filesystem itself. Do your own research before attempting to use an attribute you're not familiar with.

=cut

1;
