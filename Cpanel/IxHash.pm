package Cpanel::IxHash;    # Modified Tie::Ixhash 1.21

# Copyright (c) 2018, cPanel, L.L.C.
# All rights reserved.
# http://cpanel.net
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# 3. Neither the name of the owner nor the names of its contributors may be
# used to endorse or promote products derived from this software without
# specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#
# Gurusamy Sarathy        gsar@umich.edu
#
# Copyright (c) 1995 Gurusamy Sarathy. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

use strict;
use warnings;
use integer;

use Cpanel::Encoder::Tiny ();

our $VERSION        = '1.24';
our $Modify         = 'none';
our $QuietModify    = 0;
our $MAX_MANGLE_LEN = 64;

my %modifier = (
    'safe_html_encode'     => \&Cpanel::Encoder::Tiny::safe_html_encode_str,
    'safe_xml_encode'      => \&Cpanel::Encoder::Tiny::safe_xml_encode_str,
    'angle_bracket_encode' => \&Cpanel::Encoder::Tiny::angle_bracket_encode,
);

##
## The below modifiers are never called anywhere in cPanel, they are provided
## only for backwards compatibility, however use HTML::Entities needs to
## be called before loading this module
##
if ( $INC{'HTML/Entities.pm'} ) {
    $modifier{'html_encode'} = \&HTML::Entities::encode_entities;
    $modifier{'html_decode'} = \&HTML::Entities::decode_entities, $modifier{'safe_html_decode'} = \&Cpanel::Encoder::Tiny::safe_html_decode_str,;
}
else {
    $modifier{'html_encode'}      = \&Cpanel::Encoder::Tiny::safe_html_encode_str;
    $modifier{'html_decode'}      = \&na_modifier;
    $modifier{'safe_html_decode'} = \&na_modifier;

}

# We do not use these modifiers anywhere in cPanel, however if the module
# is loaded we make them available for legacy reasons

if ( $INC{'Cpanel/Encoder/Tiny/Rare.pm'} ) {
    $modifier{'angle_bracket_decode'} = \&Cpanel::Encoder::Tiny::Rare::angle_bracket_decode;
}

if ( $INC{'Cpanel/Encoder/URI.pm'} ) {
    $modifier{'uri_encode'} = \&Cpanel::Encoder::URI::uri_encode_str;
    $modifier{'uri_decode'} = \&Cpanel::Encoder::URI::uri_decode_str;
}

sub na_modifier {
    require Carp;
    Carp::confess("The requested modifier is not available");
}

#
# standard tie functions
#

sub TIEHASH {
    my $c = shift;
    my $s = [];

    $s->[0] = {};    # hashkey index
    $s->[1] = [];    # array of keys
    $s->[2] = [];    # array of data
    $s->[3] = 0;     # iter count

    bless $s, $c;
    $s->Push(@_) if @_;

    return $s;
}

# Empty DESTROY methods are historically used to avoid an AUTOLOAD lookup.
# Even though some perl's optimize away empty DESTROY methods we leave this
# commented out because we don't AUTOLOAD here so having it defined doesn't
# gain anything.

# sub DESTROY {}           # costly if there's nothing to do

sub FETCH {

    #Minimize variable creation by leaving these blank:
    # $self = $_[0]
    # $key  = $_[1]

    # return undef if !exists $self->[0]{$key};
    return undef if !exists $_[0]->[0]{ $_[1] };

    if ( exists $modifier{$Cpanel::IxHash::Modify} ) {

        if ( $Cpanel::CPVAR{'debug'} && $Cpanel::CPVAR{'debug'} == 1 ) {

            #my $val = $self->[2][ $self->[0]{$key} ];
            my $val = $_[0]->[2][ $_[0]->[0]{ $_[1] } ];

            print STDERR "Cpanel::IxHash: Warning, mangling data key $_[1] using $Cpanel::IxHash::Modify\n";

            if ( eval 'require bytes;1' && defined &bytes::length ) {

                my $bytes_len = bytes::length($val);
                if ( $bytes_len > $MAX_MANGLE_LEN ) {
                    my $character_msg = 'Sorry, unable to accurately count the characters';
                    if ( eval 'require Encode;1' && defined &Encode::decode_utf8 ) {
                        my $decoded              = Encode::decode_utf8($val);
                        my $number_of_characters = CORE::length($decoded);
                        $character_msg = "$number_of_characters chars";
                    }

                    require Carp;
                    print STDERR "Cpanel::IxHash: Warning, mangling data key $_[1], having length of $bytes_len bytes ($character_msg),";
                    print STDERR " which is longer than $MAX_MANGLE_LEN bytes, using $Cpanel::IxHash::Modify\n";
                    print STDERR "Cpanel::IxHash: " . Carp::longmess();
                }
            }
            else {

                print STDERR "bytes::length() was not available so the length check was skipped.\n";
            }
        }

        #return $modifier{$Cpanel::IxHash::Modify}->($val);
        return $modifier{$Cpanel::IxHash::Modify}->( $_[0]->[2][ $_[0]->[0]{ $_[1] } ] );
    }
    elsif ( $Cpanel::IxHash::Modify ne 'none' ) {
        require Carp;
        Carp::carp( 'Unknown Cpanel::IxHash::Modify: ' . $Cpanel::IxHash::Modify );
    }

    # $self->[2][ $self->[0]{$key} ];
    return $_[0]->[2][ $_[0]->[0]{ $_[1] } ];
}

sub STORE {
    my ( $self, $key, $value ) = @_;

    $key = q{} if !defined $key;

    if ( exists $self->[0]{$key} ) {
        my ($i) = $self->[0]{$key};
        $self->[1][$i]   = $key;
        $self->[2][$i]   = $value;
        $self->[0]{$key} = $i;
    }
    else {
        push( @{ $self->[1] }, $key );
        push( @{ $self->[2] }, $value );
        $self->[0]{$key} = $#{ $self->[1] };
    }
}

sub DELETE {
    my ( $s, $k ) = ( shift, shift );

    if ( exists $s->[0]{$k} ) {
        my ($i) = $s->[0]{$k};
        for ( $i + 1 .. $#{ $s->[1] } ) {    # reset higher elt indexes
            $s->[0]{ $s->[1][$_] }--;        # timeconsuming, is there is better way?
        }
        delete $s->[0]{$k};
        splice @{ $s->[1] }, $i, 1;
        return ( splice( @{ $s->[2] }, $i, 1 ) )[0];
    }
    return undef;
}

sub EXISTS {
    exists $_[0]->[0]{ $_[1] };
}

sub FIRSTKEY {
    $_[0][3] = 0;
    &NEXTKEY;
}

sub NEXTKEY {

    # $_[0] = $self
    # $self->[0] = {};    # hashkey index
    # $self->[1] = [];    # array of keys
    # $self->[2] = [];    # array of data
    # $self->[3] = 0;     # iter count
    return ( $_[0][3] <= $#{ $_[0][1] } ) ? $_[0][1][ $_[0][3]++ ] : undef;
}

sub CLEAR {
    my ($self) = @_;
    %{ $self->[0] } = ();    #key index
    @{ $self->[1] } = ();    #keys
    @{ $self->[2] } = ();    #values
    $self->[3] = 0;          #iter count
    return;
}

BEGIN {

    # For perlpkg:
    no warnings 'once';

    *new = *TIEHASH;
}

#
# add pairs to end of indexed hash
# note that if a supplied key exists, it will not be reordered
#
sub Push {
    my ($s) = shift;
    while (@_) {
        $s->STORE( shift, shift );
    }
    return scalar( @{ $s->[1] } );
}

1;

__END__

=head1 DESCRIPTION

Default if "none" thse are allowed:

  html_encode
  uri_encode
  html_decode
  uri_decode
  remove_html
  angle_bracket_encode
  angle_bracket_decode

some binaries set it to angle_bracket_encode.

=head1 USAGE

    {

        local $Cpanel::IxHash::Modify = 'none'; # rawhtmlok
        ...
