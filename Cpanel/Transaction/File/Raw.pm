package Cpanel::Transaction::File::Raw;

# cpanel - Cpanel/Transaction/File/Raw.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: Use this class for read/write operations ONLY.
#If you only need to read, then use RawReader.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw(
  Cpanel::Transaction::File::Read::Raw
  Cpanel::Transaction::File::Base
);

use Cpanel::Autodie ();

#See the note for save().
#
#This will only actually update the internal offset counter if
#a) We have no offset yet, or
#b) The passed-in offset is earlier than the one we have
sub set_first_modified_offset {
    my ( $self, $new_offset ) = @_;

    return if !defined $new_offset;

    if ( !defined $self->{'_first_modified_offset'} || $self->{'_first_modified_offset'} > $new_offset ) {
        $self->{'_first_modified_offset'} = $new_offset;
    }

    return 1;
}

#This wraps up a call to set_first_modified_offset() if you pass in a replacement.
#Arguments are the same as Perl's native substr(), minus the first argument.
sub substr {
    my ( $self, $offset, $length, $replacement ) = @_;

    my $str_ref = $self->get_data();

    # substr outside of a string
    return if ( length $$str_ref < $offset );

    if ( defined $replacement ) {
        $self->set_first_modified_offset($offset);
        return CORE::substr( $$str_ref, $offset, $length, $replacement );
    }
    elsif ( defined $length ) {
        return CORE::substr( $$str_ref, $offset, $length );
    }
    elsif ( defined $offset ) {
        return CORE::substr( $$str_ref, $offset );
    }
}

#Pass in an 'offset' parameter to save from a given point in the file.
#This can save significantly on disk I/O.
#If not passed in, we honor any offset that set_first_modified_offset()
#may have set earlier.
#NOTE: This assumes that the caller has kept track of the first point of
#modification!
sub save_or_die {
    my ( $self, %OPTS ) = @_;

    #Implementor error
    die __PACKAGE__ . ' objects can only save SCALAR references.' if ref $self->get_data() ne 'SCALAR';

    my $ret = $self->_save_or_die(
        %OPTS,
        offset   => $OPTS{'offset'} || $self->{'_first_modified_offset'} || 0,
        write_cr => \&_writer,
    );

    # We've already saved to disk so any further saves will need to have their own first modified
    # offset since we are now in sync with the file again.
    $self->{'_first_modified_offset'} = undef;

    return $ret;
}

sub _writer {
    my ( $self, $offset ) = @_;

    if ($offset) {
        require Cpanel::Autodie;
        return Cpanel::Autodie::print(
            $self->{'_fh'},
            CORE::substr( ${ $self->get_data() }, $offset ),
        );
    }

    Cpanel::Autodie::syswrite_sigguard( $self->{'_fh'}, ${ $self->get_data() } );
    return 1;
}

# Setting the complete contents invalidates any stored offset.
sub set_data {
    my ( $self, $new_data ) = @_;

    die 'must be SCALAR ref!' if 'SCALAR' ne ref $new_data;

    delete $self->{'_first_modified_offset'};

    return $self->SUPER::set_data($new_data);
}

1;
