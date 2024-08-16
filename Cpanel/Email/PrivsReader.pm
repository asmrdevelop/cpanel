package Cpanel::Email::PrivsReader;

# cpanel - Cpanel/Email/PrivsReader.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache                       ();
use Cpanel::Transaction::File::JSONReader ();
use Cpanel::Validate::Domain::Tiny        ();

my $locale;

sub _locale {
    eval 'require Cpanel::Locale' if !$INC{'Cpanel/Locale.pm'};
    return $locale ||= Cpanel::Locale->get_handle();
}

sub new {
    my ( $class, %OPTS ) = @_;

    my $domain = $OPTS{'domain'};

    if ( !length $domain ) {
        die 'The “domain” parameter is required.';
    }
    elsif ( !Cpanel::Validate::Domain::Tiny::validdomainname( $domain, 1 ) ) {
        die 'The “domain” parameter must be a valid domain.';
    }
    elsif ( $domain =~ tr{/}{} ) {
        die 'The “domain” parameter must not contain a slash.';
    }
    elsif ( $> == 0 ) {
        die "This package, " . __PACKAGE__ . ", may not be run as root.";
    }

    # We should never use this module as anyone except the user
    # because it accesses files in the users' homedir.
    my $homedir = $Cpanel::homedir || ( Cpanel::PwCache::getpwuid($>) )[7];

    my $self = bless {}, $class;

    # Domain is checked at this point to prevent a path traversal

    if ( !-e "$homedir/etc/$domain" ) {
        die _locale()->maketext( 'The system failed to locate a configuration file for the domain “[_1]”. Are you sure that this domain is installed on this server?', $domain );
    }

    my $transaction = $self->_get_transaction("$homedir/etc/$domain/_privs.json");
    $self->{'_transaction'} = $transaction;

    #convenience
    $self->{'_data'} = $transaction->get_data();

    if ( !$self->{'_data'} || ( ref $self->{'_data'} eq 'SCALAR' ) ) {
        $self->{'_data'} = {};
    }

    return $self;
}

sub _get_transaction {
    my ( $self, $path ) = @_;

    return Cpanel::Transaction::File::JSONReader->new(
        path => $path,
    );
}

sub get_mailman_list_delegates {
    my ( $self, $list ) = @_;

    die 'The “list” parameter is required.' if !length $list;

    return [] if !$self->{'_data'}{'mailman'}{$list};

    return [ sort keys %{ $self->{'_data'}{'mailman'}{$list}{'delegates'} } ];
}

sub delegate_has_access_to_mailman_list {
    my ( $self, $delegate, $list ) = @_;

    die 'The “list” parameter is required.'     if !length $list;
    die 'The “delegate” parameter is required.' if !length $delegate;

    return 0 if !$self->{'_data'}{'mailman'}{$list};

    return $self->{'_data'}{'mailman'}{$list}{'delegates'}{$delegate} ? 1 : 0;
}

sub has_delegated_mailman_lists {
    my ( $self, $delegate ) = @_;

    die 'The “delegate” parameter is required.' if !length $delegate;

    foreach my $list ( keys %{ $self->{'_data'}{'mailman'} } ) {
        if ( $self->{'_data'}{'mailman'}{$list}{'delegates'}{$delegate} ) {
            return 1;
        }
    }

    return 0;
}

1;
