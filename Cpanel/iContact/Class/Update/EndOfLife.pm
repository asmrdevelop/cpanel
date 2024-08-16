package Cpanel::iContact::Class::Update::EndOfLife;

# cpanel - Cpanel/iContact/Class/Update/EndOfLife.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::iContact::Class::FromUserAction';
use Scalar::Util 'blessed';
use Try::Tiny;
use Config                ();
use Cpanel::Update::Tiers ();
use Cpanel::Version::Full ();

my @REQUIRED_ARGS = qw(origin);

sub _get_default {
    my ($self) = @_;

    my $default = {
        starting_version      => Cpanel::Version::Full::getversion(),
        updatepreferences_url => $self->assemble_whm_url('scripts2/updateconf'),
    };

    my $tiers = Cpanel::Update::Tiers->new;

    # Used mainly in cases where the current version doesn't have an expiration date in TIERS.json
    $default->{eol_date_epoch} = $tiers->get_expires_for_version( $self->{_opts}->{starting_version} // $default->{starting_version} )
      || ( time + 1_000_000_000 );    # set expiration far in to the future, about 32 years here

    my $update_availability = $tiers->get_update_availability();
    $default->{update_available} = $update_availability->{update_available};

    return $default;
}

sub _required_args { return shift->SUPER::_required_args(@_), @REQUIRED_ARGS }

#TODO: Give customers control over this string.
sub _icontact_args {
    return shift->SUPER::_icontact_args(@_), from => 'cPanel End Of Life Notification';
}

sub _template_args {
    my ($self) = @_;

    my $default = $self->_get_default();
    my %opt     = ( %$default, %{ $self->{_opts} } );

    if ( !$opt{eol_date_epoch} ) {
        $opt{eol_date_epoch} = $default->{'eol_date_epoch'};
        if ( !$opt{eol_date_epoch} ) {
            print "Could not get default epoch of EOL for current branch.\n";
            return;
        }
    }

    $opt{'eol_date'} = gmtime( $opt{eol_date_epoch} );
    my $difference = $opt{eol_date_epoch} - time;

    # Don't override days_left if passed in as an arg, for unit testing
    if ( !defined( $opt{days_left} ) ) {
        $opt{days_left} = int( $difference / 86400 );
    }
    return ( $self->SUPER::_template_args(), %opt );
}

sub send {    # only send if within 30 days or less of EOL
    my ( $self, @args ) = @_;

    my %args = $self->_template_args();

    # don't call superclass method if outside EOL window
    return if not exists $args{eol_date_epoch};
    my $eol_date = $args{eol_date_epoch};

    # no notifications if we have more than 30 days before EOL
    if ( defined( $args{'days_left'} ) && $args{'days_left'} > 30 ) {
        return;
    }

    return $self->SUPER::send(@args);
}

1;
