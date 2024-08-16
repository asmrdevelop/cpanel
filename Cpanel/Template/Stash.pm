package Cpanel::Template::Stash;

# cpanel - Cpanel/Template/Stash.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Template::Config;
eval "require $Template::Config::STASH";    # $Template::Config::STASH is set during 'use Template::Config' but the module is not brought in
our @ISA = ($Template::Config::STASH);      # $Template::Config::STASH is set during 'use Template::Config'

sub new {
    my $class = shift();

    my $self = $Template::Config::STASH->new( 'UNDEF' => undef, @_ );

    return bless $self, $class;
}

#copied in from Template::Stash to get real undef values
#------------------------------------------------------------------------
# undefined($ident, $args)
#
# Method called when a get() returns an undefined value.  Can be redefined
# in a subclass to implement alternate handling.
#------------------------------------------------------------------------

sub undefined {
    my ( $self, $ident ) = @_;

    if ( $self->{_STRICT} ) {
        my $undef_type = eval "\$${Template::Config::STASH}::UNDEF_TYPE";
        my $undef_info = eval "\$${Template::Config::STASH}::UNDEF_INFO";

        # Sorry, but we can't provide a sensible source file and line without
        # re-designing the whole architecure of TT (see TT3)
        die Template::Exception->new(
            $undef_type,
            sprintf(
                $undef_info,
                $self->_reconstruct_ident($ident)
            )
        ) if $self->{_STRICT};
    }
    else {

        # There was a time when I thought this was a good idea. But it's not.
        # That's right. ;-)
        return undef;    #returns '' in TT2 distribution
    }
}

1;
