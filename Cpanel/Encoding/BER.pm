# -*- perl -*-

# Copyright (c) 2007 by Jeff Weisberg
# Author: Jeff Weisberg <jaw+pause @ tcp4me.com>
# Created: 2007-Jan-28 16:03 (EST)
# Function: BER encoding/decoding (also: CER and DER)
#
# $Id: BER.pm,v 1.9 2007/03/06 02:50:10 jaw Exp $

# references: ITU-T x.680 07/2002  -  ASN.1
# references: ITU-T x.690 07/2002  -  BER

# Modified heavily by cPanel to the point this module no longer tracks upstream meaningfully.

package Cpanel::Encoding::BER;

use strict;
use warnings;

our $VERSION = '1.00';
use constant DEBUG_AVAILABLE => 0;    #only enable if needed

# loaded on demand if needed:
#   POSIX
# used if already loaded:
#   Math::BigInt

=head1 NAME

Encoding::BER - Perl module for encoding/decoding data using ASN.1 Basic Encoding Rules (BER)

=head1 SYNOPSIS

  use Encoding::BER;
  my $enc = Encoding::BER->new();
  my $ber = $enc->encode( $data );
  my $xyz = $enc->decode( $ber );

=head1 DESCRIPTION

Unlike many other BER encoder/decoders, this module uses tree structured data
as the interface to/from the encoder/decoder.

The decoder does not require any form of template or description of the
data to be decoded. Given arbitrary BER encoded data, the decoder produces
a tree shaped perl data structure from it.

The encoder takes a perl data structure and produces a BER encoding from it.

=head1 METHODS

=over 4

=cut

################################################################

my %CLASS = (
    universal   => { v => 0, },
    application => { v => 0x40, },
    context     => { v => 0x80, },
    private     => { v => 0xC0, },
);

my %TYPE = (
    primitive   => { v => 0, },
    constructed => { v => 0x20, },
);

my %TAG = (
    universal => {
        content_end       => { v => 0, },
        boolean           => { v => 1,   e        => \&encode_bool,   d => \&decode_bool },
        integer           => { v => 2,   e        => \&encode_int,    d => \&decode_int },
        bit_string        => { v => 3,   e        => \&encode_bits,   d => \&decode_bits,   dc => \&reass_string, rule => 1 },
        octet_string      => { v => 4,   e        => \&encode_string, d => \&decode_string, dc => \&reass_string, rule => 1 },
        null              => { v => 5,   e        => \&encode_null,   d => \&decode_null },
        oid               => { v => 6,   e        => \&encode_oid,    d => \&decode_oid },
        object_descriptor => { v => 7,   implicit => 'octet_string' },
        external          => { v => 8,   type     => ['constructed'] },
        enumerated        => { v => 0xA, implicit => 'integer' },
        embedded_pdv      => { v => 0xB, e        => \&encode_string, d => \&decode_string, dc => \&reass_string },
        utf8_string       => { v => 0xC, implicit => 'octet_string' },
        relative_oid      => { v => 0xD, e        => \&encode_roid, d => \&decode_roid },

        # reserved
        # reserved
        sequence         => { v => 0x10, type     => ['constructed'] },
        set              => { v => 0x11, type     => ['constructed'] },
        numeric_string   => { v => 0x12, implicit => 'octet_string' },
        printable_string => { v => 0x13, implicit => 'octet_string' },
        teletex_string   => { v => 0x14, implicit => 'octet_string' },
        videotex_string  => { v => 0x15, implicit => 'octet_string' },
        ia5_string       => { v => 0x16, implicit => 'octet_string' },
        universal_time   => { v => 0x17, implicit => 'octet_string' },
        generalized_time => { v => 0x18, implicit => 'octet_string' },
        graphic_string   => { v => 0x19, implicit => 'octet_string' },
        visible_string   => { v => 0x1a, implicit => 'octet_string' },
        general_string   => { v => 0x1b, implicit => 'octet_string' },
        universal_string => { v => 0x1c, implicit => 'octet_string' },
        character_string => { v => 0x1d, implicit => 'octet_string' },
        bmp_string       => { v => 0x1e, implicit => 'octet_string' },
    },

    private => {

        # extra.
        # no, the encode/decode functions are not mixed up.
        # yes, this module handles large tag-numbers.
        integer32      => { v => 0xFFF0, type => ['private'], e => \&encode_uint32, d => \&decode_int },
        unsigned_int   => { v => 0xFFF1, type => ['private'], e => \&encode_uint,   d => \&decode_uint },
        unsigned_int32 => { v => 0xFFF2, type => ['private'], e => \&encode_uint32, d => \&decode_uint },
    },
);

# synonyms
my %AKATAG = (
    bool                       => 'boolean',
    int                        => 'integer',
    string                     => 'octet_string',
    object_identifier          => 'oid',
    relative_object_identifier => 'relative_oid',
    roid                       => 'relative_oid',
    float                      => 'real',
    enum                       => 'enumerated',
    sequence_of                => 'sequence',
    set_of                     => 'set',
    t61_string                 => 'teletex_string',
    iso646_string              => 'visible_string',
    int32                      => 'integer32',
    unsigned_integer           => 'unsigned_int',
    uint                       => 'unsigned_int',
    uint32                     => 'unsigned_int32',

    # ...
);

# insert name into above data
my %ALLTAG;
my %REVTAG;

# insert name + class into above data
# build reverse map, etc.
init_tag_lookups( \%TAG, \%ALLTAG, \%REVTAG );

my %REVCLASS = map { ( $CLASS{$_}{v} => $_ ) } keys %CLASS;

my %REVTYPE = map { ( $TYPE{$_}{v} => $_ ) } keys %TYPE;

################################################################

=item new(option => value, ...)

constructor.

    example:
    my $enc = Encoding::BER->new( error => sub{ die "$_[1]\n" } );

the following options are available:

=over 4

=item error

coderef called if there is an error. will be called with 2 parameters,
the Encoding::BER object, and the error message.

    # example: die on error
    error => sub{ die "oops! $_[1]\n" }

=item warn

coderef called if there is something to warn about. will be called with 2 parameters,
the Encoding::BER object, and the error message.

    # example: warn for warnings
    warn => sub{ warn "how odd! $_[1]\n" }


=item decoded_callback

coderef called for every element decoded. will be called with 2 parameters,
the Encoding::BER object, and the decoded data. [see DECODED DATA]

    # example: bless decoded results into a useful class
    decoded_callback => sub{ bless $_[1], MyBER::Result }

=item debug

boolean. if true, large amounts of useless gibberish will be sent to stderr regarding
the encoding or decoding process.

    # example: enable gibberish output
    debug => 1

=back

=cut

sub new {
    my $cl = shift;
    my $me = bless {@_}, $cl;

    return $me;
}

sub error {
    my $me  = shift;
    my $msg = shift;

    if ( my $f = $me->{error} ) {
        $f->( $me, $msg );
    }
    else {
        require Carp;
        Carp::croak( ( ref $me ) . ": $msg\n" );
    }
    return undef;
}

sub warn {
    my $me  = shift;
    my $msg = shift;

    if ( my $f = $me->{warn} ) {
        $f->( $me, $msg );
    }
    else {
        require Carp;
        Carp::carp( ( ref $me ) . ": $msg\n" );
    }
    return undef;
}

sub debug {
    my $me  = shift;
    my $msg = shift;

    return unless $me->{debug};
    print STDERR "  " x $me->{level}, $msg, "\n";
    return undef;
}

################################################################

sub add_tag_hash {    ## no critic(ProhibitManyArgs)
    my $me    = shift;
    my $class = shift;
    my $type  = shift;
    my $name  = shift;
    my $num   = shift;
    my $data  = shift;

    return $me->error("invalid class: $class") unless $CLASS{$class};
    return $me->error("invalid type: $type")   unless $TYPE{$type};

    $data->{type} = [ $class, $type ];
    $data->{v}    = $num;
    $data->{n}    = $name;

    # install forward + reverse mappings
    $me->{tags}{$name} = $data;
    $me->{revtags}{$class}{$num} = $name;

    return $me;
}

=item add_implicit_tag(class, type, tag-name, tag-number, base-tag)

add a new tag similar to another tag. class should be one of C<universal>,
C<application>, C<context>, or C<private>. type should be either C<primitive>
or C<contructed>. tag-name should specify the name of the new tag.
tag-number should be the numeric tag number. base-tag should specify the
name of the tag this is equivalent to.

    example: add a tagged integer
    in ASN.1: width-index ::= [context 42] implicit integer

    $ber->add_implicit_tag('context', 'primitive', 'width-index', 42, 'integer');

=cut

sub add_implicit_tag {    ## no critic(ProhibitManyArgs)
    my $me    = shift;
    my $class = shift;
    my $type  = shift;
    my $name  = shift;
    my $num   = shift;
    my $base  = shift;

    return $me->error("unknown base tag name: $base")
      unless $me->tag_data_byname($base);

    return $me->add_tag_hash(
        $class, $type, $name, $num,
        {
            implicit => $base,
        }
    );
}

sub add_tag {    ## no critic(ProhibitManyArgs)
    my $me    = shift;
    my $class = shift;
    my $type  = shift;
    my $name  = shift;
    my $num   = shift;

    # possibly optional:
    my $encf  = shift;
    my $decf  = shift;
    my $encfc = shift;
    my $decfc = shift;

    return $me->add_tag_hash(
        $class, $type, $name, $num,
        {
            e  => $encf,
            d  => $decf,
            ec => $encfc,
            dc => $decfc,
        }
    );
}

sub init_tag_lookups {
    my $TAG = shift;
    my $ALL = shift;
    my $REV = shift;

    for my $class ( keys %$TAG ) {
        for my $name ( keys %{ $TAG->{$class} } ) {
            $TAG->{$class}{$name}{n} = $name;
            $ALL->{$name} = $TAG->{$class}{$name};
        }
        my %d = map { ( $TAG->{$class}{$_}{v} => $_ ) } keys %{ $TAG->{$class} };
        $REV->{$class} = \%d;
    }
    return;
}

################################################################

# tags added via add_tag method
sub app_tag_data_byname {
    my $me   = shift;
    my $name = shift;

    return $me->{tags}{$name};
}

# override me in subclass
sub subclass_tag_data_byname {
    my $me   = shift;
    my $name = shift;

    return undef;
}

# from the table up top
sub univ_tag_data_byname {

    #my $me    = shift;
    #my $name  = shift;
    return $ALLTAG{ $_[1] } || ( $AKATAG{ $_[1] } && $ALLTAG{ $AKATAG{ $_[1] } } );
}

sub tag_data_byname {
    my $me   = shift;
    my $name = shift;

    my $th;

    # application specific tag name
    $th = $me->app_tag_data_byname($name);

    # subclass specific tag name
    $th = $me->subclass_tag_data_byname($name) unless $th;

    # universal tag name
    $th = $me->univ_tag_data_byname($name) unless $th;

    return $th;
}

################################################################

=item decode( ber )

Decode the provided BER encoded data. returns a perl data structure.
[see: DECODED DATA]

  example:
  my $data = $enc->decode( $ber );

=cut

sub decode {
    my ( $me, $data ) = @_;

    $me->{level} = 0;

    if ( ref $me eq __PACKAGE__ ) {    # If we are not subclassed, skip app specific and subclassed lookups
        no warnings 'redefine';
        local *tag_data_byname   = *univ_tag_data_byname;
        local *tag_data_bynumber = *univ_tag_data_bynumber;
        my ( $v, $l ) = $me->decode_item( $data, 0 );
        return $v;
    }

    my ( $v, $l ) = $me->decode_item( $data, 0 );
    return $v;
}

sub decode_items {
    my ( $me, $data, $eocp, $levl ) = @_;
    my @v;
    my $tlen = 0;

    $me->{level} = $levl;
    $me->debug("decode items[") if DEBUG_AVAILABLE;
    while ($data) {
        my ( $val, $len ) = $me->decode_item( $data, $levl + 1 );
        $tlen += $len;
        unless ( $val && defined $val->{type} ) {

            # end-of-content
            $me->debug('end of content') if DEBUG_AVAILABLE;
            last                         if $eocp;
        }

        push @v, $val;
        substr( $data, 0, $len, '' );
    }

    $me->{level} = $levl;
    $me->debug(']') if DEBUG_AVAILABLE;
    return ( \@v, $tlen );
}

sub decode_item {
    my ( $me, $data, $levl ) = @_;

    # hexdump($data, 'di:');
    $me->{level} = $levl;
    my ( $typval, $typlen, $typmore ) = ( ord($data), 1 );
    if ( ( $typval & 0x1f ) == 0x1f ) {    # This is very rare, avoid decode_ident unless we need to
        ( $typval, $typlen, $typmore ) = $me->decode_ident($data);
    }
    my ( $typdat, $decfnc, $pretty, $tagnum ) = $me->ident_descr_and_dfuncs( $typval, $typmore );
    my $length_byte = substr( $data, $typlen );
    my ( $datlen, $lenlen ) = ( ord($length_byte), 1 );
    if ( $datlen & 0x80 ) {                # Most lengths are x.690 8.1.3.4 - short form so avoid decode unless needed
        ( $datlen, $lenlen ) = $me->decode_length( substr( $data, $typlen ) );
    }
    my $havlen = length($data);
    my $tlen   = $typlen + $lenlen + ( $datlen || 0 );
    my $doff   = $typlen + $lenlen;
    my $result;

    $me->error("corrupt data? data appears truncated")
      if $havlen < $tlen;

    if ( $typval & 0x20 ) {

        # constructed
        my $vals;

        if ( defined $datlen ) {

            # definite
            $me->debug("decode item: constructed definite [@$typdat($tagnum)]") if DEBUG_AVAILABLE;
            my ( $v, $t ) = $me->decode_items( substr( $data, $doff, $datlen ), 0, $levl );
            $me->{level} = $levl;
            $me->warn("corrupt data? item len != data len ($t, $datlen)")
              unless $t == $datlen;
            $vals = $v;
        }
        else {
            # indefinite
            $me->debug("decode item: constructed indefinite [@$typdat($tagnum)]") if DEBUG_AVAILABLE;
            my ( $v, $t ) = $me->decode_items( substr( $data, $doff ), 1, $levl );
            $me->{level} = $levl;
            $tlen += $t;
            $tlen += 2;    # eoc
            $vals = $v;
        }
        if ($decfnc) {

            # constructed decode func: reassemble
            $result = $decfnc->( $me, $vals, $typdat );
        }
        else {
            $result = {
                value => $vals,
            };
        }
    }
    else {
        # primitive
        my $ndat;
        if ( defined $datlen ) {

            # definite
            $me->debug("decode item: primitive definite [@$typdat($tagnum)]") if DEBUG_AVAILABLE;
            $ndat = substr( $data, $doff, $datlen );
        }
        else {
            # indefinite encoding of a primitive is a violation of x.690 8.1.3.2(a)
            # warn + parse it anyway
            $me->debug("decode item: primitive indefinite [@$typdat($tagnum)]") if DEBUG_AVAILABLE;
            $me->warn("protocol violation - indefinite encoding of primitive. see x.690 8.1.3.2(a)");
            my $i = index( $data, "\0\0", $doff );
            if ( $i == -1 ) {

                # invalid encoding.
                # no eoc found.
                # go back to protocol school.
                $me->error("corrupt data - content terminator not found. see x.690 8.1.3.6, 8.1.5, et al. ");
                return ( undef, $tlen );
            }
            my $dl = $i - $doff;
            $tlen += $dl;
            $tlen += 2;     # eoc
            $ndat = substr( $data, $doff, $dl );
        }

        unless ( $typval || $typmore ) {

            # universal-primitive-tag(0) => end-of-content
            return ( {}, $tlen );
        }

        # decode it
        $decfnc ||= \&decode_unknown;
        my $val = $decfnc->( $me, $ndat, $typdat );
        $val->{binary} = \$ndat;    #cpanel

        # format value in a special pretty way?
        if ($pretty) {
            $val = $pretty->( $me, $val ) || $val;
        }
        $result = $val;
    }

    @{$result}{ 'type', 'tagnum', 'identval' } = ( $typdat, $tagnum, $typval );

    if ( my $c = $me->{decoded_callback} ) {
        $result = $c->( $me, $result ) || $result;    # make sure the brain hasn't fallen out
    }
    return ( $result, $tlen );
}

sub app_tag_data_bynumber {
    my $me    = shift;
    my $class = shift;
    my $tnum  = shift;

    my $name = $me->{revtags}{$class}{$tnum};
    return unless $name;

    return $me->{tags}{$name};
}

# override me in subclass
sub subclass_tag_data_bynumber {
    my $me    = shift;
    my $class = shift;
    my $tnum  = shift;

    return undef;
}

sub univ_tag_data_bynumber {

    #    my $me    = shift;
    #    my $class = shift;
    #    my $tnum  = shift;
    no warnings;    ## no critic qw(TestingAndDebugging::ProhibitNoWarnings)
    return $TAG{ $_[1] }{ $REVTAG{ $_[1] }{ $_[2] } };
}

sub tag_data_bynumber {
    my ( $me, $class, $tnum ) = @_;

    my $th;

    # application specific tag name
    $th = $me->app_tag_data_bynumber( $class, $tnum );

    # subclass specific tag name
    $th = $me->subclass_tag_data_bynumber( $class, $tnum ) unless $th;

    # from universal
    $th = $me->univ_tag_data_bynumber( $class, $tnum ) unless $th;

    return $th;
}

sub ident_descr_and_dfuncs {
    my ( $me, $tval, $more ) = @_;

    my $tag   = $more || ( $tval & 0x1f ) || 0;
    my $cl    = $tval & 0xC0;
    my $ty    = $tval & 0x20;
    my $class = $REVCLASS{$cl};
    my $pctyp = $REVTYPE{$ty};

    my ( $th, $tn, $tf, $tp );

    {
        no warnings;    ## no critic qw(TestingAndDebugging::ProhibitNoWarnings)
        $th = $TAG{$class}{ $REVTAG{$class}{$tag} };
    }

    #$th = $me->tag_data_bynumber($class, $tag);

    if ( ref $th ) {
        $tn = $th->{n};
        $tp = $th->{pretty};

        if ( my $impl = $th->{implicit} ) {

            # indirect. we support only one level.
            my $h = $ALLTAG{$impl} || ( $AKATAG{$impl} && $ALLTAG{ $AKATAG{$impl} } );

            #my $h = $me->tag_data_byname($impl);
            if ( ref $h ) {
                $th = $h;
                $tp ||= $th->{pretty};
            }
            else {
                $me->error("programmer botch. implicit indirect not found: $class/$tn => $impl");
            }
        }

        # primitive decode func or constructed decode func?
        $tf = $ty ? $th->{dc} : $th->{d};
    }
    elsif ($th) {
        $me->error("programmer botch. tag data should be hashref: $class/$tag => $th");
    }
    elsif ( $class ne 'context' ) {
        $me->warn("unknown type [$class $tag]");
    }

    $tn = $tag unless defined $tn;

    $me->debug("identifier $tval/$tag resolved to [$class $pctyp $tn]") if DEBUG_AVAILABLE;

    # [class, type, tagname], decodefunc, tagnumber
    return ( [ $class, $pctyp, $tn ], $tf, $tp, $tag );
}

sub decode_length {
    my ( $me, $data ) = @_;

    my $l1 = ord($data);

    unless ( $l1 & 0x80 ) {

        # x.690 8.1.3.4 - short form
        return ( $l1, 1 );
    }
    if ( $l1 == 0x80 ) {

        # x.690 8.1.3.6 - indefinite form
        return ( undef, 1 );
    }

    # x.690 8.1.3.5 - long form
    my $llen = $l1 & 0x7f;

    #The length is always recorded as a big-endian integer.
    if ( $llen == 1 ) {
        return ( ord( substr( $data, 1 ) ), 2 );
    }
    elsif ( $llen == 2 ) {
        return ( unpack( 'x1n', $data ), 3 );
    }
    elsif ( $llen < 5 ) {
        substr( $data, 1, 0, "\0" ) if $llen == 3;
        return ( unpack( 'x1N', $data ), $llen + 1 );
    }
    elsif ( $llen < 9 ) {
        substr( $data, 1, 0, "\0" x ( 8 - $llen ) ) if $llen < 8;
        return ( unpack( 'x1Q>', $data ), $llen + 1 );
    }

    my $len = 0;
    $len = ( $len <<= 8 ) + $_ for unpack( "x1C$llen", $data );

    return ( $len, $llen + 1 );
}

sub decode_ident {
    my ( $me, $data ) = @_;

    my $tag = ord($data);
    return ( $tag, 1 ) unless ( $tag & 0x1f ) == 0x1f;    # x.690 8.1.2.3

    # x.690 8.1.2.4 - tag numbers > 30
    my $i = 1;
    $tag &= ~0x1f;
    my $more = 0;
    while (1) {
        my $c = unpack( 'C', substr( $data, $i++, 1 ) );
        $more <<= 7;
        $more |= ( $c & 0x7f );
        last unless $c & 0x80;
    }

    return ( $tag, $i, $more );
}

sub decode_bool {
    my ( $me, $data, $type ) = @_;

    my $v = ord($data);

    return {
        value => $v,
    };
}

sub decode_null {
    return {
        value => undef,
    };
}

# reassemble constructed string
sub reass_string {
    my $me   = shift;
    my $vals = shift;
    my $type = shift;

    my $val = '';
    for my $v (@$vals) {
        $val .= $v->{value};
    }

    $me->debug('reassemble constructed string') if DEBUG_AVAILABLE;
    return {
        type  => [ $type->[0], 'primitive', $type->[2] ],
        value => $val,
    };

}

sub decode_string {

    #my $me   = shift;
    #my $data = shift;
    #my $type = shift;

    return {
        value => $_[1],
    };
}

sub decode_bits {
    my ( $me, $data, $type ) = @_;

    # my $pad = ord($data);
    # QQQ - remove padding?

    return {
        value => substr( $data, 1 ),
    };
}

sub decode_int {
    my ( $me, $data, $type ) = @_;

    # ints are limited to 8 bytes
    # perl cannot hold numbers larger and
    # we do not have Math::Bigint support here
    # so just return 'inf' when asked to decode
    # something that will efectively return
    # garbage.
    return { value => 'inf' } if length($data) > 8;

    my $val = unpack( 'c', $data );
    $val = ( $val * 256 ) + $_ for unpack( 'x1C*', $data );

    $me->debug("decode integer: $val") if DEBUG_AVAILABLE;
    return {
        value => $val,
    };
}

sub decode_uint {
    my ( $me, $data, $type ) = @_;

    my $val = ord($data);
    if ( length $data > 1 ) {
        $val = ( $val * 256 ) + $_ for unpack( 'x1C*', $data );
    }

    $me->debug("decode unsigned integer: $val") if DEBUG_AVAILABLE;
    return {
        value => $val,
    };
}

my %_oids;

sub decode_oid {
    my ( $me, $data, $type ) = @_;

    my @o = unpack( 'w*', $data );
    my $val;

    if ( $o[0] < 40 ) {
        $val = '0.' . join( '.', @o );
    }
    elsif ( $o[0] < 80 ) {
        $o[0] -= 40;
        $val = '1.' . join( '.', @o );
    }
    else {
        $o[0] -= 80;
        $val = '2.' . join( '.', @o );
    }

    $me->debug("decode oid: $val") if DEBUG_AVAILABLE;

    return (
        $_oids{$val} ||= {
            value => $val,
        }
    );
}

sub decode_roid {
    my ( $me, $data, $type ) = @_;

    my @o = unpack( 'w*', $data );

    my $val = join( '.', @o );
    $me->debug("decode relative-oid: $val") if DEBUG_AVAILABLE;

    return {
        value => $val,
    };
}

sub decode_unknown {
    my ( $me, $data, $type ) = @_;

    $me->debug("decode unknown") if DEBUG_AVAILABLE;
    return {
        value => $data,
    };
}

################################################################

sub hexdump {
    my $b   = shift;
    my $tag = shift;
    my ( $l, $t );

    print STDERR "$tag:\n" if $tag;
    while ($b) {
        $t = $l = substr( $b, 0, 16, '' );
        $l =~ s/(.)/sprintf('%0.2X ',ord($1))/ges;
        $l =~ s/(.{24})/$1 /;
        $t =~ s/[[:^print:]]/./gs;
        my $p = ' ' x ( 49 - ( length $l ) );
        print STDERR "    $l  $p$t\n";
    }
    return;
}

sub import {
    my $pkg    = shift;
    my $caller = caller;

    for my $f (@_) {
        no strict;    ## no critic(ProhibitNoStrict)
        my $fnc = $pkg->can($f);
        next unless $fnc;
        *{ $caller . '::' . $f } = $fnc;
    }
    return;
}

sub DESTROY { }

=back

=head1 ENCODING DATA

You can give data to the encoder in either of two ways (or mix and match).

You can specify simple values directly, and the module will guess the
correct tags to use. Things that look like integers will be encoded as
C<integer>, things that look like floating-point numbers will be encoded
as C<real>, things that look like strings, will be encoded as C<octet_string>.
Arrayrefs will be encoded as C<sequence>.

  example:
  $enc->encode( [0, 1.2, "foobar", [ "baz", 37.94 ]] );

Alternatively, you can explicity specify the type using a hashref
containing C<type> and C<value> keys.

  example:
  $enc->encode( { type  => 'sequence',
                  value => [
                             { type  => 'integer',
                               value => 37 } ] } );

The type may be specfied as either a string containg the tag-name, or
as an arryref containing the class, type, and tag-name.

  example:
  type => 'octet_string'
  type => ['universal', 'primitive', 'octet_string']

Note: using the second form above, you can create wacky encodings
that no one will be able to decode.

The value should be a scalar value for primitive types, and an
arrayref for constructed types.

  example:
  { type => 'octet_string', value => 'foobar' }
  { type => 'set', value => [ 1, 2, 3 ] }

  { type  => ['universal', 'constructed', 'octet_string'],
    value => [ 'foo', 'bar' ] }

=head1 DECODED DATA

The values returned from decoding will be similar to the way data to
be encoded is specified, in the full long form. Additionally, the hashref
will contain: C<identval> the numeric value representing the class+type+tag
and C<tagnum> the numeric tag number.

  example:
  a string might be returned as:
  { type     => ['universal', 'primitive', 'octet_string'],
    identval => 4,
    tagnum   => 4,
    value    => 'foobar',
  }


=head1 TAG NAMES

The following are recognized as valid names of tags:

    bit_string bmp_string bool boolean character_string embedded_pdv
    enum enumerated external float general_string generalized_time
    graphic_string ia5_string int int32 integer integer32 iso646_string
    null numeric_string object_descriptor object_identifier octet_string
    oid printable_string real relative_object_identifier relative_oid
    roid sequence sequence_of set set_of string t61_string teletex_string
    uint uint32 universal_string universal_time unsigned_int unsigned_int32
    unsigned_integer utf8_string videotex_string visible_string

=head1 Math::BigInt

If you have Math::BigInt, it can be used for large integers. If you want it used,
you must load it yourself:

    use Math::BigInt;
    use Encoding::BER;

It can be used for both encoding and decoding. The encoder can be handed either
a Math::BigInt object, or a "big string of digits" marked as an integer:

    use math::BigInt;

    my $x = Math::BigInt->new( '12345678901234567890' );
    $enc->encode( $x )

    $enc->encode( { type => 'integer', '12345678901234567890' } );

During decoding, a Math::BigInt object will be created if the value "looks big".


=head1 EXPORTS

By default, this module exports nothing. This can be overridden by specifying
something else:

    use Encoding::BER ('import', 'hexdump');

=head1 LIMITATIONS

If your application uses the same tag-number for more than one type of implicitly
tagged primitive, the decoder will not be able to distinguish between them, and will
not be able to decode them both correctly. eg:

    width ::= [context 12] implicit integer
    girth ::= [context 12] implicit real

If you specify data to be encoded using the "short form", the module may
guess the type differently than you expect. If it matters, be explicit.

This module does not do data validation. It will happily let you encode
a non-ascii string as a C<ia5_string>, etc.


=head1 PREREQUISITES

If you wish to use C<real>s, the POSIX module is required. It will be loaded
automatically, if needed.

Familiarity with ASN.1 and BER encoding is probably required to take
advantage of this module.

=head1 SEE ALSO

    Yellowstone National Park
    Encoding::BER::CER, Encoding::BER::DER
    Encoding::BER::SNMP, Encoding::BER::Dumper
    ITU-T x.690

=head1 AUTHOR

    Jeff Weisberg - http://www.tcp4me.com

=cut

################################################################
1;

