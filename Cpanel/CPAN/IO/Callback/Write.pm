package Cpanel::CPAN::IO::Callback::Write;

#Copyright 1998-2005 Gisle Aas.
#
#Copyright 2009-2010 Dave Taylor.
#
#This program is free software; you can redistribute it and/or modify it
#under the same terms as Perl itself.

#----------------------------------------------------------------------
# Use this class to catch output that would normally be sent to a filehandle
# and send it instead to a callback function.
#
# Most of this module is copied from IO::Callback 1.10. It doesn't do reading
# or many other things that IO::Callback itself does, but it's also lighter.
#----------------------------------------------------------------------

use strict;

use Symbol ();

sub new {
    my ( $class, $callback ) = @_;

    my $self = bless Symbol::gensym(), ref($class) || $class;
    tie *$self, $self;

    *$self->{'_callback'} = $callback;

    return $self;
}

sub TIEHANDLE {
    return $_[0] if ref( $_[0] );
    my $class = shift;
    my $self = bless Symbol::gensym(), $class;
    return $self;
}

sub fileno {
    return -1;    #This is what fileno() on a scalar ref filehandle returns.
}

sub close { }

#copied and tweaked slightly
sub write {
    my $self = shift;

    my $slen = length( $_[0] );
    my $len  = $slen;
    my $off  = 0;
    if ( @_ > 1 ) {
        my $xlen = defined $_[1] ? $_[1] : 0;
        $len = $xlen if $xlen < $len;
        die "Negative length" if $len < 0;
        if ( @_ > 2 ) {
            $off = $_[2] || 0;
            if ( $off >= $slen and $off > 0 and ( $] < 5.011 or $off > $slen ) ) {
                die "Offset outside string";
            }
            if ( $off < 0 ) {
                $off += $slen;
                die "Offset outside string" if $off < 0;
            }
            my $rem = $slen - $off;
            $len = $rem if $rem < $len;
        }
    }
    if ($len) {
        *$self->{'_callback'}( substr $_[0], $off, $len );
    }
    return $len;
}

sub print {
    my $self = shift;

    my $result;
    if ( defined $\ ) {
        if ( scalar @_ == 1 ) {
            $result = $self->WRITE( $_[0] . $\ );
        }
        elsif ( defined $, ) {
            $result = $self->WRITE( join( $,, @_ ) . $\ );
        }
        else {
            $result = $self->WRITE( join( "", @_ ) . $\ );
        }
    }
    else {
        if ( scalar @_ == 1 ) {
            $result = $self->WRITE( $_[0] );
        }
        elsif ( defined $, ) {
            $result = $self->WRITE( join( $,, @_ ) );
        }
        else {
            $result = $self->WRITE( join( "", @_ ) );
        }
    }

    return unless defined $result;
    return 1;
}

sub printf {
    my $self   = shift;
    my $fmt    = shift;
    my $result = $self->WRITE( sprintf( $fmt, @_ ) );
    return unless defined $result;
    return 1;
}

*CLOSE  = *close;
*FILENO = *fileno;
*PRINT  = *print;
*PRINTF = *printf;
*WRITE  = *write;

1;
