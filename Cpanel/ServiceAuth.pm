package Cpanel::ServiceAuth;

# cpanel - Cpanel/ServiceAuth.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#
# This needs to be ultra light weight on memory
# because it gets included in dormat services

our $KEY_SIZE = 16;
our $NO_WAIT  = 1;

# This needs to mirror Cpanel::ConfigFiles but
# not include it for memory reasons
our $SERVICEAUTH_DIR = '/var/cpanel/serviceauth';

BEGIN {
    # BEGIN makes  scripts/updatenow.static happy
    *fetch_passkey = *fetch_recvkey;
    *fetch_userkey = *fetch_sendkey;
}

sub new {
    my $class   = shift;
    my $service = shift;
    my $self    = {};
    bless $self, $class;

    if ( defined $service ) {
        $service =~ tr{/}{}d;
        $self->{'service'} = $service;
    }

    return $self;
}

sub set_service {
    my ( $self, $service ) = @_;

    $service =~ tr{/}{}d;
    return ( $self->{'service'} = $service );
}

sub verify_dirs {
    my $self = shift;
    if ( !-e $SERVICEAUTH_DIR ) {
        mkdir( $SERVICEAUTH_DIR, 0711 );
    }

    chmod( 0711, $SERVICEAUTH_DIR );

    if ( !-e "$SERVICEAUTH_DIR/" . $self->{"service"} ) {
        if ( $self->{"service"} eq "exim" || $self->{"service"} eq "smtp" ) {
            require Cpanel::PwCache;
            my $mailgid = ( Cpanel::PwCache::getpwnam_noshadow('mail') )[3];
            mkdir( "$SERVICEAUTH_DIR/" . $self->{"service"}, 0750 );
            chown 0, $mailgid, "$SERVICEAUTH_DIR/" . $self->{"service"};
        }
        else {
            mkdir( "$SERVICEAUTH_DIR/" . $self->{"service"}, 0700 );
        }
    }

    return;
}

sub generate_authkeys_if_missing {
    my ($self) = @_;
    if (  !-e "$SERVICEAUTH_DIR/$self->{service}/recv"
        || -s _ < $KEY_SIZE
        || !-e "$SERVICEAUTH_DIR/$self->{service}/send"
        || -s _ < $KEY_SIZE ) {

        return $self->generate_authkeys();
    }
    return;
}

sub generate_authkeys {
    my $self = shift;

    $self->verify_dirs();

    require Cpanel::Rand::Get;

    open( my $recvkey_fh, ">", "$SERVICEAUTH_DIR/" . $self->{"service"} . "/recv" );
    print {$recvkey_fh} Cpanel::Rand::Get::getranddata($KEY_SIZE);
    close($recvkey_fh);

    open( my $sendkey_fh, ">", "$SERVICEAUTH_DIR/" . $self->{"service"} . "/send" );
    print {$sendkey_fh} Cpanel::Rand::Get::getranddata($KEY_SIZE);
    close($sendkey_fh);
}

sub fetch_recvkey {
    my $self = shift;
    return $self->_fetchkey( 'recv', @_ );
}

sub fetch_sendkey {
    my $self = shift;
    return $self->_fetchkey( 'send', @_ );
}

# This may block for up to 6 seconds
sub _fetchkey {
    my $self = shift;
    my $key  = shift;
    my $opt  = shift;

    $key =~ tr{/}{}d;
    my $file = "$SERVICEAUTH_DIR/" . $self->{'service'} . '/' . $key;
    #
    # It would be nice if this was atomic.  Right now we wait to make sure a key
    # is at least 6 seconds old before using it to ensure the service that wrote it
    # is ready to use it.   We have a NO_WAIT flag for keys that we write out which
    # is current only used in ChkServd
    #
    if ( defined $opt && $opt != $NO_WAIT ) {
        my $now   = time();
        my $count = 0;
        while ( ( $now - ( stat($file) )[9] ) < 6 ) {
            sleep 1;
            if ( ++$count >= 10 ) { last; }
        }
    }
    if ( open( my $fh, '<', $file ) ) {
        local $/;
        return readline($fh);

        # no close needed here becuase it will be closed when out of scope
    }
    return;
}

1;
